import CoreGraphics
import Foundation
import Observation

/// A photo as handed to the app: where it is on disk and the name the user knows it by.
public struct PhotoSource: Sendable, Equatable {
    public var url: URL
    /// The photo's file name as the user knows it; the export is named after it.
    public var originalName: String

    public init(url: URL, originalName: String) {
        self.url = url
        self.originalName = originalName
    }
}

/// One photo of the batch. Only a thumbnail is kept in memory; larger images are read from
/// `source` when needed.
public struct PhotoItem: Identifiable {
    public let id: UUID
    public let source: PhotoSource
    /// Upright pixel size of the full image.
    public let pixelSize: CGSize
    /// Upright; longest side ≤ 320 px.
    public let thumbnail: CGImage
    public var placements: [EmojiPlacement]
    /// Head detection has not finished yet.
    public var isDetecting: Bool
    /// Position of the photo's source among all sources ever given to the batch; `photos` is
    /// kept sorted by it.
    let sequence: Int
}

/// The photos being worked on and every edit to them. State changes only on the main actor;
/// loading and head detection run off it.
@MainActor @Observable
public final class Batch {
    public private(set) var photos: [PhotoItem] = []
    /// Setting it clears `selectedEmojiID`.
    public var currentPhotoID: PhotoItem.ID? {
        didSet { selectedEmojiID = nil }
    }
    /// An emoji of the current photo. Cleared when that emoji is removed by any edit or undo.
    public var selectedEmojiID: EmojiPlacement.ID?
    /// Placed on newly detected heads and by `addEmoji()`; changing it leaves placed emoji alone.
    public var defaultEmoji = EmojiCatalog.defaultEmoji
    /// A head found only by its upper body, its face unseen, gets an emoji when the body's confidence
    /// is above this (see `HeadPlacement.placements`): lower covers more such heads, and more things
    /// that are not heads; 1 covers faces only. Changing it leaves placed emoji alone.
    public var bodyConfidenceThreshold = HeadPlacement.defaultBodyConfidenceThreshold
    /// Receives every undoable edit; nil makes edits not undoable.
    public var undoManager: UndoManager?

    public var currentPhoto: PhotoItem? {
        currentPhotoID.flatMap(photoIndex).map { photos[$0] }
    }

    /// Some `add` call has not returned: its photos are still waiting their turn, loading or being
    /// scanned for heads.
    public var isBusy: Bool { activeAdds > 0 }

    /// One job per photo, in photo order.
    public var exportJobs: [ExportJob] {
        photos.map { ExportJob(source: $0.source.url, originalName: $0.source.originalName, placements: $0.placements) }
    }

    private static let maxConcurrentPhotos = 4

    private let detector: any HeadDetecting
    /// `add` calls that have not returned, including those waiting for their turn.
    private var activeAdds = 0
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var addInProgress = false
    @ObservationIgnored private var addsWaiting: [CheckedContinuation<Void, Never>] = []
    /// Detection results for photos removed while their detection ran, kept for an undo that
    /// brings the photo back.
    @ObservationIgnored private var detectedWhileRemoved: [PhotoItem.ID: [EmojiPlacement]] = [:]

    public init(detector: any HeadDetecting = VisionHeadDetector()) {
        self.detector = detector
    }

    // MARK: - Adding photos

    /// Loads `sources` and appends their photos in the order given, even when a later source
    /// finishes loading first. Each photo appears as soon as its thumbnail has loaded, with
    /// `isDetecting` set; detection then runs on a copy with longest side ≤ 4096 px and places
    /// `defaultEmoji` on each head found, using `defaultEmoji` and `bodyConfidenceThreshold` as they
    /// are when that detection finishes. A photo removed
    /// before its detection finishes does not get the result unless the removal is undone.
    /// Undecodable sources are skipped. Whenever nothing is current, the call's earliest photo
    /// becomes current as soon as no earlier source of the call is still loading, so the first
    /// decodable source's photo is picked whatever the load order.
    /// At most 4 photos are processed at once; overlapping calls take turns, in call order.
    /// Await it from a task that is not cancelled. Cancelling does not stop loading, but it may
    /// cut detection short; such a photo keeps `isDetecting` set rather than appearing to have no one in it.
    /// Returns the number of sources skipped. Not undoable.
    @discardableResult
    public func add(_ sources: [PhotoSource]) async -> Int {
        guard !sources.isEmpty else { return 0 }
        let firstSequence = nextSequence
        nextSequence += sources.count
        activeAdds += 1
        defer { activeAdds -= 1 }
        await waitForTurn()
        defer { passTurn() }
        return await intake(sources, firstSequence: firstSequence)
    }

    private func intake(_ sources: [PhotoSource], firstSequence: Int) async -> Int {
        var skipped = 0
        let ownSequences = firstSequence..<(firstSequence + sources.count)
        var isLoading = [Bool](repeating: true, count: sources.count)
        var firstLoading = 0
        /// Run after each source finishes loading or fails to.
        func pickCurrentPhotoIfNone() {
            while firstLoading < isLoading.count, !isLoading[firstLoading] { firstLoading += 1 }
            guard currentPhotoID == nil,
                  let earliest = photos.first(where: { ownSequences.contains($0.sequence) }),
                  earliest.sequence - firstSequence < firstLoading
            else { return }
            currentPhotoID = earliest.id
        }

        await withTaskGroup(of: IntakeStep.self) { group in
            var nextSource = 0
            func loadNextSource() {
                guard nextSource < sources.count else { return }
                let index = nextSource, url = sources[index].url
                nextSource += 1
                group.addTask {
                    guard let loaded = await PhotoIntake.load(url) else { return .undecodable(sourceIndex: index) }
                    return .loaded(sourceIndex: index, loaded)
                }
            }
            for _ in 0..<Self.maxConcurrentPhotos { loadNextSource() }

            while let step = await group.next() {
                switch step {
                case let .loaded(index, loaded):
                    let photo = PhotoItem(
                        id: UUID(), source: sources[index], pixelSize: loaded.pixelSize, thumbnail: loaded.thumbnail,
                        placements: [], isDetecting: true, sequence: firstSequence + index
                    )
                    insert(photo)
                    isLoading[index] = false
                    pickCurrentPhotoIfNone()
                    // The load's slot passes to this photo's detection.
                    let detector = detector, id = photo.id, url = photo.source.url, size = photo.pixelSize
                    group.addTask {
                        .detected(id, imageSize: size, await PhotoIntake.detect(in: url, using: detector))
                    }
                case let .undecodable(index):
                    skipped += 1
                    isLoading[index] = false
                    pickCurrentPhotoIfNone()
                    loadNextSource()
                case let .detected(id, imageSize, detection):
                    finishDetection(of: id, imageSize: imageSize, detection)
                    loadNextSource()
                }
            }
        }
        return skipped
    }

    /// Applied directly, not as an undo step. `detection` is nil when cancellation cut detection
    /// short: the photo then stays `isDetecting`.
    private func finishDetection(of id: PhotoItem.ID, imageSize: CGSize, _ detection: Detection?) {
        guard let detection else { return }
        let detected = HeadPlacement.placements(
            for: detection, imageSize: imageSize, emoji: defaultEmoji, bodyConfidenceThreshold: bodyConfidenceThreshold
        )
        if let index = photoIndex(id) {
            photos[index].placements += detected
            photos[index].isDetecting = false
        } else {
            detectedWhileRemoved[id] = detected
        }
    }

    /// Puts `photo` where its sequence belongs, keeping `photos` in source order.
    private func insert(_ photo: PhotoItem) {
        photos.insert(photo, at: photos.firstIndex { $0.sequence > photo.sequence } ?? photos.endIndex)
    }

    private func waitForTurn() async {
        if addInProgress {
            await withCheckedContinuation { addsWaiting.append($0) }
        }
        addInProgress = true
    }

    private func passTurn() {
        if addsWaiting.isEmpty {
            addInProgress = false
        } else {
            addsWaiting.removeFirst().resume()
        }
    }

    // MARK: - Editing

    /// Undoable. The current photo moves to the next photo, else the previous, else nil.
    public func removePhoto(_ id: PhotoItem.ID) {
        guard let index = photoIndex(id) else { return }
        let photo = photos.remove(at: index)
        if currentPhotoID == id {
            currentPhotoID = index < photos.endIndex ? photos[index].id : photos.last?.id
        }
        undoManager?.registerUndo(withTarget: self) { $0.restore(photo) }
        undoManager?.setActionName("Remove Photo")
    }

    /// Undoable. Removes every photo, leaving none current. Does nothing while `isBusy`: photos still
    /// being added would turn up after it.
    public func removeAllPhotos() {
        guard !isBusy else { return }
        removePhotos(Set(photos.map(\.id)))
    }

    /// Removes the photos `ids` names and registers their return. Should the current photo go, the first
    /// photo left, if any, becomes current. Redoing `removeAllPhotos` lands here with only the photos it
    /// removed, so that photos added since stay.
    private func removePhotos(_ ids: Set<PhotoItem.ID>) {
        let removed = photos.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        let current = currentPhotoID
        photos.removeAll { ids.contains($0.id) }
        if let current, ids.contains(current) { currentPhotoID = photos.first?.id }
        undoManager?.registerUndo(withTarget: self) { $0.restore(removed, current: current) }
        undoManager?.setActionName("Remove All Photos")
    }

    /// Undoes `removePhotos`: the photos come back in source order, among any added since, and the
    /// photo that was current when they went becomes current again, else the first of them.
    private func restore(_ removed: [PhotoItem], current: PhotoItem.ID?) {
        for photo in removed { insert(photo) }
        currentPhotoID = removed.contains { $0.id == current } ? current : removed[0].id
        undoManager?.registerUndo(withTarget: self) { $0.removePhotos(Set(removed.map(\.id))) }
        undoManager?.setActionName("Remove All Photos")
    }

    /// Undoes `removePhoto`: the photo comes back with its placements, in source order, and becomes
    /// current. Source order is its old index, unless a still-running `add` has since inserted an
    /// earlier source's photo; then it lands after that photo, keeping `photos` in source order.
    private func restore(_ removed: PhotoItem) {
        var photo = removed
        if photo.isDetecting, let detected = detectedWhileRemoved.removeValue(forKey: photo.id) {
            photo.placements += detected
            photo.isDetecting = false
        }
        insert(photo)
        currentPhotoID = photo.id
        undoManager?.registerUndo(withTarget: self) { $0.removePhoto(photo.id) }
        undoManager?.setActionName("Remove Photo")
    }

    /// Undoable. Puts `defaultEmoji` in the middle of the current photo, sized as the median of
    /// its emoji (a fifth of its shorter side if it has none), and selects it.
    public func addEmoji() {
        guard let photo = currentPhoto else { return }
        let placement = EmojiPlacement(
            emoji: defaultEmoji, center: CGPoint(x: 0.5, y: 0.5), size: Self.newEmojiSize(in: photo)
        )
        setPlacement(placement.id, to: placement, in: photo.id, actionName: "Add Emoji")
        selectedEmojiID = placement.id
    }

    /// Undoable. Removes the selected emoji of the current photo and clears the selection.
    public func deleteSelectedEmoji() {
        guard let photoID = currentPhotoID, let selected = selectedEmojiID else { return }
        setPlacement(selected, to: nil, in: photoID, actionName: "Delete Emoji")
        selectedEmojiID = nil
    }

    /// Undoable. Replaces the placement with `placement.id` (a move, resize or emoji change).
    /// Does nothing if there is no such placement or nothing changed.
    public func update(_ placement: EmojiPlacement, in photoID: PhotoItem.ID) {
        guard let index = photoIndex(photoID),
              let old = photos[index].placements.first(where: { $0.id == placement.id }),
              old != placement
        else { return }
        setPlacement(placement.id, to: placement, in: photoID, actionName: "Change Emoji")
    }

    /// Makes the placement `id` of the photo be `placement` (nil: absent) and registers the
    /// inverse, which registers redo in turn. Undo and redo first make the photo current, so a
    /// change is never applied out of sight. A placement that was absent goes in at
    /// `insertionIndex`, clamped, or at the end. The undo snapshot is this one placement rather
    /// than the photo's whole list, so emoji detected between an edit and its undo survive the undo.
    private func setPlacement(_ id: EmojiPlacement.ID, to placement: EmojiPlacement?, at insertionIndex: Int? = nil,
                              in photoID: PhotoItem.ID, actionName: String) {
        guard let index = photoIndex(photoID) else { return }
        var placements = photos[index].placements
        let oldIndex = placements.firstIndex { $0.id == id }
        let old = oldIndex.map { placements[$0] }
        switch (oldIndex, placement) {
        case (nil, nil): return
        case let (i?, new?): placements[i] = new
        case let (i?, nil): placements.remove(at: i)
        case let (nil, new?): placements.insert(new, at: min(insertionIndex ?? placements.endIndex, placements.endIndex))
        }
        photos[index].placements = placements
        if placement == nil, selectedEmojiID == id { selectedEmojiID = nil }
        undoManager?.registerUndo(withTarget: self) { batch in
            if batch.currentPhotoID != photoID, batch.photoIndex(photoID) != nil { batch.currentPhotoID = photoID }
            batch.setPlacement(id, to: old, at: oldIndex, in: photoID, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    private static func newEmojiSize(in photo: PhotoItem) -> CGFloat {
        let sizes = photo.placements.map(\.size).sorted()
        guard !sizes.isEmpty else {
            return 0.2 * min(photo.pixelSize.width, photo.pixelSize.height) / photo.pixelSize.width
        }
        let middle = sizes.count / 2
        return sizes.count.isMultiple(of: 2) ? (sizes[middle - 1] + sizes[middle]) / 2 : sizes[middle]
    }

    // MARK: - Navigation

    /// Stops at the last photo. Does nothing when no photo is current.
    public func selectNextPhoto() { selectPhoto(offset: 1) }

    /// Stops at the first photo. Does nothing when no photo is current.
    public func selectPreviousPhoto() { selectPhoto(offset: -1) }

    private func selectPhoto(offset: Int) {
        guard let current = currentPhotoID.flatMap(photoIndex) else { return }
        let target = min(max(current + offset, 0), photos.count - 1)
        if target != current { currentPhotoID = photos[target].id }
    }

    private func photoIndex(_ id: PhotoItem.ID) -> Int? {
        photos.firstIndex { $0.id == id }
    }
}

/// What a child task of `Batch.add` reports back to the main actor.
private enum IntakeStep: Sendable {
    case loaded(sourceIndex: Int, PhotoIntake.Loaded)
    case undecodable(sourceIndex: Int)
    /// nil when cancellation cut detection short.
    case detected(PhotoItem.ID, imageSize: CGSize, Detection?)
}

/// The steps of adding a photo that run off the main actor.
private enum PhotoIntake {
    /// `CGImage` is `Sendable` in the SDK, so the thumbnail can cross to the main actor as is.
    struct Loaded: Sendable {
        var pixelSize: CGSize
        var thumbnail: CGImage
    }

    static let thumbnailMaxPixelSize = 320
    static let detectionMaxPixelSize = 4096

    /// nil when the file cannot be decoded as an image.
    @concurrent static func load(_ url: URL) async -> Loaded? {
        guard let pixelSize = try? ImageLoader.uprightPixelSize(of: url),
              let thumbnail = try? ImageLoader.loadUpright(url, maxPixelSize: thumbnailMaxPixelSize)
        else { return nil }
        return Loaded(pixelSize: pixelSize, thumbnail: thumbnail)
    }

    /// Detection on a copy with longest side ≤ 4096 px; nothing found if that copy cannot be loaded or
    /// detection fails; nil if detection failed because the task was cancelled, so that the photo is
    /// not taken to have no one in it.
    @concurrent static func detect(in url: URL, using detector: any HeadDetecting) async -> Detection? {
        guard let image = try? ImageLoader.loadUpright(url, maxPixelSize: detectionMaxPixelSize) else { return Detection() }
        do {
            return try await detector.detect(in: image)
        } catch {
            return Task.isCancelled ? nil : Detection()
        }
    }
}
