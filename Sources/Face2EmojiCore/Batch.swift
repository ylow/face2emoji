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
    /// Face detection has not finished yet.
    public var isDetecting: Bool
    /// Position of the photo's source among all sources ever given to the batch; `photos` is
    /// kept sorted by it.
    let sequence: Int
}

/// The photos being worked on and every edit to them. State changes only on the main actor;
/// loading and face detection run off it.
@MainActor @Observable
public final class Batch {
    public private(set) var photos: [PhotoItem] = []
    /// Setting it clears `selectedEmojiID`.
    public var currentPhotoID: PhotoItem.ID? {
        didSet { selectedEmojiID = nil }
    }
    /// An emoji of the current photo. Cleared when that emoji is removed by any edit or undo.
    public var selectedEmojiID: EmojiPlacement.ID?
    /// Placed on newly detected faces and by `addEmoji()`; changing it leaves placed emoji alone.
    public var defaultEmoji = EmojiCatalog.defaultEmoji
    /// Receives every undoable edit; nil makes edits not undoable.
    public var undoManager: UndoManager?

    public var currentPhoto: PhotoItem? {
        currentPhotoID.flatMap(photoIndex).map { photos[$0] }
    }

    /// Some `add` call has not returned: its photos are still waiting their turn, loading or being
    /// scanned for faces.
    public var isBusy: Bool { activeAdds > 0 }

    /// One job per photo, in photo order.
    public var exportJobs: [ExportJob] {
        photos.map { ExportJob(source: $0.source.url, originalName: $0.source.originalName, placements: $0.placements) }
    }

    private static let maxConcurrentPhotos = 4

    private let detector: any FaceDetecting
    /// `add` calls that have not returned, including those waiting for their turn.
    private var activeAdds = 0
    @ObservationIgnored private var nextSequence = 0
    @ObservationIgnored private var addInProgress = false
    @ObservationIgnored private var addsWaiting: [CheckedContinuation<Void, Never>] = []
    /// Detection results for photos removed while their detection ran, kept for an undo that
    /// brings the photo back.
    @ObservationIgnored private var detectedWhileRemoved: [PhotoItem.ID: [EmojiPlacement]] = [:]

    public init(detector: any FaceDetecting = VisionFaceDetector()) {
        self.detector = detector
    }

    // MARK: - Adding photos

    /// Loads `sources` and appends their photos in the order given, even when a later source
    /// finishes loading first. Each photo appears as soon as its thumbnail has loaded, with
    /// `isDetecting` set; detection then runs on a copy with longest side ≤ 4096 px and places
    /// `defaultEmoji` — as it is when that detection finishes — on each face. A photo removed
    /// before its detection finishes does not get the result unless the removal is undone.
    /// Undecodable sources are skipped. If nothing is current, the photo of the first decodable
    /// source becomes current once it has loaded.
    /// At most 4 photos are processed at once; overlapping calls take turns, in call order.
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
        // If nothing is current, the first decodable source's photo becomes current, so the pick
        // waits until every source before it has turned out undecodable, whatever the load order.
        var outcomes = [SourceOutcome](repeating: .loading, count: sources.count)
        var firstUndecided = 0
        func pickCurrentPhoto() {
            while firstUndecided < outcomes.count {
                switch outcomes[firstUndecided] {
                case .loading:
                    return
                case .skipped:
                    firstUndecided += 1
                case .added(let id):
                    if currentPhotoID == nil, photoIndex(id) != nil { currentPhotoID = id }
                    firstUndecided = outcomes.count
                }
            }
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
                    outcomes[index] = .added(photo.id)
                    pickCurrentPhoto()
                    // The load's slot passes to this photo's detection.
                    let detector = detector, id = photo.id, url = photo.source.url, size = photo.pixelSize
                    group.addTask {
                        .detected(id, imageSize: size, faces: await PhotoIntake.detectFaces(in: url, using: detector))
                    }
                case let .undecodable(index):
                    skipped += 1
                    outcomes[index] = .skipped
                    pickCurrentPhoto()
                    loadNextSource()
                case let .detected(id, imageSize, faces):
                    finishDetection(of: id, imageSize: imageSize, faces: faces)
                    loadNextSource()
                }
            }
        }
        return skipped
    }

    /// Applied directly, not as an undo step.
    private func finishDetection(of id: PhotoItem.ID, imageSize: CGSize, faces: [DetectedFace]) {
        let detected = faces.map { FacePlacement.placement(for: $0, imageSize: imageSize, emoji: defaultEmoji) }
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
    /// inverse, which registers redo in turn. A placement that was absent goes in at
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

/// What a source has come to so far in one `add` call.
private enum SourceOutcome {
    case loading, skipped, added(PhotoItem.ID)
}

/// What a child task of `Batch.add` reports back to the main actor.
private enum IntakeStep: Sendable {
    case loaded(sourceIndex: Int, PhotoIntake.Loaded)
    case undecodable(sourceIndex: Int)
    case detected(PhotoItem.ID, imageSize: CGSize, faces: [DetectedFace])
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

    /// Faces on a copy with longest side ≤ 4096 px; none if that copy cannot be loaded or detection fails.
    @concurrent static func detectFaces(in url: URL, using detector: any FaceDetecting) async -> [DetectedFace] {
        guard let image = try? ImageLoader.loadUpright(url, maxPixelSize: detectionMaxPixelSize) else { return [] }
        return (try? await detector.detectFaces(in: image)) ?? []
    }
}
