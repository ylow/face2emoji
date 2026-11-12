import CoreGraphics
import Foundation
import Synchronization
import Testing
import Face2EmojiCore

/// Reports `faces` and `bodies` for every image, unless the task is cancelled, as Vision does.
struct StubDetector: HeadDetecting {
    var faces: [DetectedFace] = [DetectedFace(box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), roll: nil)]
    var bodies: [DetectedBody] = []
    /// When set, `detect` waits for one element first. Only one detection may wait on a gate.
    var gate: AsyncStream<Void>? = nil
    /// When set, `detect` waits until it opens. Any number of detections may wait on it.
    var latch: Latch? = nil

    func detect(in image: CGImage) async throws -> Detection {
        if let gate {
            for await _ in gate { break }
        }
        await latch?.wait()
        try Task.checkCancellation()
        return Detection(faces: faces, bodies: bodies)
    }
}

/// Holds everyone who waits until `open()`; after that, waiting returns at once.
final class Latch: Sendable {
    private let state = Mutex<(isOpen: Bool, waiting: [CheckedContinuation<Void, Never>])>((false, []))

    func wait() async {
        await withCheckedContinuation { continuation in
            let isOpen = state.withLock { state in
                if !state.isOpen { state.waiting.append(continuation) }
                return state.isOpen
            }
            if isOpen { continuation.resume() }
        }
    }

    func open() {
        let waiting = state.withLock { state in
            state.isOpen = true
            defer { state.waiting = [] }
            return state.waiting
        }
        for continuation in waiting { continuation.resume() }
    }
}

/// Finds no one, slowly, and records the most detections ever running at once.
private final class CountingDetector: HeadDetecting {
    private let counts = Mutex((running: 0, peak: 0))
    var peak: Int { counts.withLock { $0.peak } }

    func detect(in image: CGImage) async throws -> Detection {
        counts.withLock { $0.running += 1; $0.peak = max($0.peak, $0.running) }
        defer { counts.withLock { $0.running -= 1 } }
        try await Task.sleep(for: .milliseconds(20))
        return Detection()
    }
}

/// A decodable JPEG known to the user as `name`.
private func source(_ name: String, width: Int = 640, height: Int = 480) throws -> PhotoSource {
    PhotoSource(url: try TestImages.writeJPEG(width: width, height: height), originalName: name)
}

/// A file known to the user as `name` that is not an image.
private func garbageSource(_ name: String) throws -> PhotoSource {
    let url = tempURL(name)
    try Data("not an image".utf8).write(to: url)
    return PhotoSource(url: url, originalName: name)
}

/// An undo manager whose groups the test closes itself, one per simulated user event:
/// tests do not spin the run loop that closes groups by event.
@MainActor private func manualUndoManager() -> UndoManager {
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    return undoManager
}

@MainActor private func asOneEvent(_ undoManager: UndoManager, _ body: () -> Void) {
    undoManager.beginUndoGrouping()
    body()
    undoManager.endUndoGrouping()
}

@MainActor @Test func addPlacesDefaultEmojiOnEachFace() async throws {
    let batch = Batch(detector: StubDetector())
    let skipped = try await batch.add([source("a.jpg"), source("b.jpg")])
    #expect(skipped == 0)
    #expect(batch.photos.map(\.source.originalName) == ["a.jpg", "b.jpg"])
    #expect(batch.photos.allSatisfy { $0.placements.map(\.emoji) == ["😀"] && !$0.isDetecting })
    #expect(batch.currentPhotoID == batch.photos[0].id)
    #expect(!batch.isBusy)
    #expect(max(batch.photos[0].thumbnail.width, batch.photos[0].thumbnail.height) <= 320)
    #expect(batch.photos[0].pixelSize == CGSize(width: 640, height: 480))
}

@MainActor @Test func addSkipsUndecodableFiles() async throws {
    let batch = Batch(detector: StubDetector())
    let skipped = try await batch.add([source("a.jpg"), garbageSource("b.jpg"), source("c.jpg")])
    #expect(skipped == 1)
    #expect(batch.photos.map(\.source.originalName) == ["a.jpg", "c.jpg"])
}

@MainActor @Test func addKeepsSourceOrderWhenLaterSourcesLoadFirst() async throws {
    // The large first photo takes far longer to decode than the tiny ones started beside it.
    let batch = Batch(detector: StubDetector())
    let sources = try [source("big.jpg", width: 6000, height: 4000)]
        + (1...5).map { try source("small\($0).jpg", width: 16, height: 16) }
    await batch.add(sources)
    #expect(batch.photos.map(\.source) == sources)
    #expect(batch.currentPhotoID == batch.photos[0].id)
}

@MainActor @Test func overlappingAddsProcessAtMostFourPhotosAtOnce() async throws {
    let detector = CountingDetector()
    let batch = Batch(detector: detector)
    let first = try (1...6).map { try source("a\($0).jpg", width: 16, height: 16) }
    let second = try (1...6).map { try source("b\($0).jpg", width: 16, height: 16) }
    async let addingFirst = batch.add(first)
    async let addingSecond = batch.add(second)
    _ = await (addingFirst, addingSecond)
    #expect(batch.photos.count == 12)
    #expect(detector.peak <= 4)
    #expect(detector.peak > 1)      // photos are processed in parallel, not one by one
}

@MainActor @Test func photoLoadedAfterEveryOtherWasRemovedBecomesCurrent() async throws {
    let latch = Latch()
    let batch = Batch(detector: StubDetector(latch: latch))
    let sources = try (1...5).map { try source("p\($0).jpg", width: 16, height: 16) }
    let adding = Task { await batch.add(sources) }
    // Four photos load and their detections hold all four slots, so the fifth cannot load yet.
    while batch.photos.count < 4 { await Task.yield() }
    for photo in batch.photos { batch.removePhoto(photo.id) }
    #expect(batch.photos.isEmpty && batch.currentPhotoID == nil)
    latch.open()
    _ = await adding.value
    #expect(batch.photos.map(\.source) == [sources[4]])
    #expect(batch.currentPhotoID == batch.photos.first?.id)
    #expect(batch.currentPhotoID != nil)
}

@MainActor @Test func cancelledDetectionLeavesPhotoDetecting() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let batch = Batch(detector: StubDetector(gate: stream))
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    adding.cancel()
    _ = await adding.value
    #expect(batch.photos.count == 1)
    #expect(batch.photos[0].isDetecting)
    #expect(batch.photos[0].placements.isEmpty)
    #expect(!batch.isBusy)
    cont.finish()
}

@MainActor @Test func secondAddAppendsAndKeepsCurrent() async throws {
    let batch = Batch(detector: StubDetector())
    try await batch.add([source("a.jpg")])
    let a = batch.photos[0].id
    try await batch.add([source("b.jpg")])
    #expect(batch.photos.map(\.source.originalName) == ["a.jpg", "b.jpg"])
    #expect(batch.currentPhotoID == a)
}

@MainActor @Test func changedDefaultAppliesToLaterPhotosOnly() async throws {
    let batch = Batch(detector: StubDetector())
    try await batch.add([source("a.jpg")])
    batch.defaultEmoji = "🤖"
    try await batch.add([source("b.jpg")])
    #expect(batch.photos[0].placements.map(\.emoji) == ["😀"])
    #expect(batch.photos[1].placements.map(\.emoji) == ["🤖"])
    #expect(batch.currentPhotoID == batch.photos[0].id)
    batch.addEmoji()
    #expect(batch.photos[0].placements.map(\.emoji) == ["😀", "🤖"])
}

@MainActor @Test func defaultIsReadWhenDetectionFinishes() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let batch = Batch(detector: StubDetector(gate: stream))
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    batch.defaultEmoji = "🤖"
    cont.yield(); _ = await adding.value
    #expect(batch.photos[0].placements.map(\.emoji) == ["🤖"])
}

/// A face and, far from it, a body of confidence 0.5 whose face was not found.
private let faceAndFacelessBody = StubDetector(bodies: [DetectedBody(box: CGRect(x: 0.05, y: 0.1, width: 0.2, height: 0.5), confidence: 0.5)])

@MainActor @Test func bodyThresholdAppliesToLaterPhotosOnly() async throws {
    let batch = Batch(detector: faceAndFacelessBody)
    try await batch.add([source("a.jpg")])
    batch.bodyConfidenceThreshold = 0.6
    try await batch.add([source("b.jpg")])
    #expect(batch.photos[0].placements.count == 2)
    #expect(batch.photos[1].placements.count == 1)
}

@MainActor @Test func bodyThresholdIsReadWhenDetectionFinishes() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    var detector = faceAndFacelessBody
    detector.gate = stream
    let batch = Batch(detector: detector)
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    batch.bodyConfidenceThreshold = 1
    cont.yield(); _ = await adding.value
    #expect(batch.photos[0].placements.count == 1)
}

@MainActor @Test func removeDuringDetectionDiscardsResult() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let batch = Batch(detector: StubDetector(gate: stream))
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    #expect(batch.photos[0].isDetecting && batch.isBusy)
    batch.removePhoto(batch.photos[0].id)
    cont.yield(); _ = await adding.value
    #expect(batch.photos.isEmpty && batch.currentPhotoID == nil && !batch.isBusy)
}

@MainActor @Test func undoingRemovalAfterDetectionFinishedRestoresDetectedEmoji() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector(gate: stream))
    batch.undoManager = undoManager
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    let id = batch.photos[0].id
    asOneEvent(undoManager) { batch.removePhoto(id) }
    cont.yield(); _ = await adding.value
    undoManager.undo()
    #expect(batch.photos.map(\.id) == [id])
    #expect(batch.currentPhotoID == id)
    #expect(!batch.photos[0].isDetecting)
    #expect(batch.photos[0].placements.map(\.emoji) == ["😀"])
}

@MainActor @Test func undoingRemovalBeforeDetectionFinishesStillGetsDetectedEmoji() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector(gate: stream))
    batch.undoManager = undoManager
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    let id = batch.photos[0].id
    asOneEvent(undoManager) { batch.removePhoto(id) }
    undoManager.undo()
    #expect(batch.photos.map(\.id) == [id])
    #expect(batch.photos[0].isDetecting)
    cont.yield(); _ = await adding.value
    #expect(!batch.photos[0].isDetecting)
    #expect(batch.photos[0].placements.map(\.emoji) == ["😀"])
}

@MainActor @Test func undoingEditMadeDuringDetectionKeepsDetectedEmoji() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector(gate: stream))
    batch.undoManager = undoManager
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    asOneEvent(undoManager) { batch.addEmoji() }
    let added = try #require(batch.selectedEmojiID)
    cont.yield(); _ = await adding.value
    #expect(batch.photos[0].placements.count == 2)
    undoManager.undo()
    let remaining = batch.photos[0].placements
    #expect(remaining.count == 1)
    #expect(!remaining.contains { $0.id == added })
}

@MainActor @Test func addEmojiUsesMedianSizeOrFifthOfShortSide() async throws {
    let batch = Batch(detector: StubDetector(faces: []))
    try await batch.add([source("wide.jpg", width: 400, height: 200)])
    let photoID = try #require(batch.currentPhotoID)

    batch.addEmoji()
    let first = try #require(batch.currentPhoto?.placements.first)
    #expect(first.size == 0.2 * 200 / 400)
    #expect(first.size == 0.1)
    #expect(first.center == CGPoint(x: 0.5, y: 0.5))
    #expect(batch.selectedEmojiID == first.id)
    #expect(first.emoji == batch.defaultEmoji)

    batch.addEmoji()
    batch.addEmoji()
    let placements = try #require(batch.currentPhoto?.placements)
    for (placement, size) in zip(placements, [0.1, 0.3, 0.5] as [CGFloat]) {
        var resized = placement
        resized.size = size
        batch.update(resized, in: photoID)
    }
    #expect(batch.currentPhoto?.placements.map(\.size) == [0.1, 0.3, 0.5])
    batch.addEmoji()
    #expect(batch.currentPhoto?.placements.last?.size == 0.3)
}

@MainActor @Test func editsAreUndoable() async throws {
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector())
    batch.undoManager = undoManager
    try await batch.add([source("a.jpg")])
    let photoID = try #require(batch.currentPhotoID)
    let detected = batch.photos[0].placements[0]

    var moved = detected
    moved.center = CGPoint(x: 0.25, y: 0.75)
    asOneEvent(undoManager) { batch.update(moved, in: photoID) }
    #expect(batch.photos[0].placements == [moved])
    #expect(undoManager.undoActionName == "Change Emoji")
    undoManager.undo()
    #expect(batch.photos[0].placements[0].center == detected.center)
    undoManager.redo()
    #expect(batch.photos[0].placements[0].center == moved.center)

    batch.selectedEmojiID = moved.id
    asOneEvent(undoManager) { batch.deleteSelectedEmoji() }
    #expect(batch.photos[0].placements.isEmpty && batch.selectedEmojiID == nil)
    #expect(undoManager.undoActionName == "Delete Emoji")
    undoManager.undo()
    #expect(batch.photos[0].placements == [moved])

    asOneEvent(undoManager) { batch.addEmoji() }
    #expect(batch.photos[0].placements.count == 2)
    #expect(undoManager.undoActionName == "Add Emoji")
    undoManager.undo()
    #expect(batch.photos[0].placements == [moved])
    #expect(batch.selectedEmojiID == nil)   // the selected emoji is gone

    var replaced = moved
    replaced.emoji = "🤖"
    asOneEvent(undoManager) { batch.update(replaced, in: photoID) }
    #expect(batch.photos[0].placements == [replaced])
    #expect(undoManager.undoActionName == "Change Emoji")
}

@MainActor @Test func undoAndRedoOfEmojiEditShowTheEditedPhoto() async throws {
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector())
    batch.undoManager = undoManager
    try await batch.add([source("a.jpg"), source("b.jpg")])
    let (a, b) = (batch.photos[0].id, batch.photos[1].id)
    let before = batch.photos[0].placements
    asOneEvent(undoManager) { batch.addEmoji() }
    let after = batch.photos[0].placements

    batch.currentPhotoID = b
    undoManager.undo()
    #expect(batch.currentPhotoID == a)
    #expect(batch.photos[0].placements == before)

    batch.currentPhotoID = b
    undoManager.redo()
    #expect(batch.currentPhotoID == a)
    #expect(batch.photos[0].placements == after)
}

@MainActor @Test func removePhotoMovesCurrentAndUndoRestoresPosition() async throws {
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector())
    batch.undoManager = undoManager
    try await batch.add([source("a.jpg"), source("b.jpg"), source("c.jpg")])
    let (a, b, c) = (batch.photos[0].id, batch.photos[1].id, batch.photos[2].id)
    batch.currentPhotoID = b
    asOneEvent(undoManager) { batch.addEmoji() }
    let bPlacements = batch.photos[1].placements

    asOneEvent(undoManager) { batch.removePhoto(b) }
    #expect(batch.photos.map(\.id) == [a, c])
    #expect(batch.currentPhotoID == c)
    #expect(undoManager.undoActionName == "Remove Photo")
    undoManager.undo()
    #expect(batch.photos.map(\.id) == [a, b, c])
    #expect(batch.currentPhotoID == b)
    #expect(batch.photos[1].placements == bPlacements)

    asOneEvent(undoManager) { batch.removePhoto(c) }
    #expect(batch.photos.map(\.id) == [a, b])
    #expect(batch.currentPhotoID == b)          // c was not current
    asOneEvent(undoManager) { batch.removePhoto(b) }
    #expect(batch.currentPhotoID == a)

    asOneEvent(undoManager) { batch.removePhoto(a) }
    #expect(batch.photos.isEmpty)
    #expect(batch.currentPhotoID == nil)
}

@MainActor @Test func removeAllPhotosEmptiesTheBatchAndUndoRestoresIt() async throws {
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector())
    batch.undoManager = undoManager
    try await batch.add([source("a.jpg"), source("b.jpg"), source("c.jpg")])
    let ids = batch.photos.map(\.id)
    batch.currentPhotoID = ids[1]
    asOneEvent(undoManager) { batch.addEmoji() }
    let placements = batch.photos.map(\.placements)

    asOneEvent(undoManager) { batch.removeAllPhotos() }
    #expect(batch.photos.isEmpty)
    #expect(batch.currentPhotoID == nil)
    #expect(undoManager.undoActionName == "Remove All Photos")

    undoManager.undo()
    #expect(batch.photos.map(\.id) == ids)
    #expect(batch.photos.map(\.placements) == placements)
    #expect(batch.currentPhotoID == ids[1])

    undoManager.redo()
    #expect(batch.photos.isEmpty)
    #expect(batch.currentPhotoID == nil)
}

@MainActor @Test func undoingRemoveAllKeepsPhotosAddedSinceAndRedoRemovesOnlyTheOldOnes() async throws {
    let undoManager = manualUndoManager()
    let batch = Batch(detector: StubDetector())
    batch.undoManager = undoManager
    try await batch.add([source("a.jpg"), source("b.jpg")])
    let old = batch.photos.map(\.id)
    asOneEvent(undoManager) { batch.removeAllPhotos() }
    try await batch.add([source("c.jpg")])
    let new = batch.photos.map(\.id)

    undoManager.undo()
    #expect(batch.photos.map(\.id) == old + new)    // source order: a and b were given first
    #expect(batch.currentPhotoID == old[0])

    undoManager.redo()
    #expect(batch.photos.map(\.id) == new)
    #expect(batch.currentPhotoID == new[0])
}

@MainActor @Test func removeAllPhotosDoesNothingWhileBusy() async throws {
    let (stream, cont) = AsyncStream<Void>.makeStream()
    let batch = Batch(detector: StubDetector(gate: stream))
    let a = try source("a.jpg")
    let adding = Task { await batch.add([a]) }
    while batch.photos.isEmpty { await Task.yield() }
    batch.removeAllPhotos()
    #expect(batch.photos.count == 1)
    cont.yield(); _ = await adding.value
}

@MainActor @Test func navigationClampsAndClearsSelection() async throws {
    let batch = Batch(detector: StubDetector())
    try await batch.add([source("a.jpg"), source("b.jpg")])
    let (a, b) = (batch.photos[0].id, batch.photos[1].id)
    #expect(batch.currentPhotoID == a)
    batch.selectedEmojiID = batch.photos[0].placements[0].id

    batch.selectNextPhoto()
    #expect(batch.currentPhotoID == b)
    #expect(batch.selectedEmojiID == nil)
    batch.selectNextPhoto()
    #expect(batch.currentPhotoID == b)
    batch.selectPreviousPhoto()
    batch.selectPreviousPhoto()
    #expect(batch.currentPhotoID == a)
}

@MainActor @Test func exportJobsFollowPhotoOrder() async throws {
    let batch = Batch(detector: StubDetector())
    try await batch.add([source("a.jpg"), source("b.jpg"), source("c.jpg")])
    batch.currentPhotoID = batch.photos[1].id
    batch.addEmoji()
    let jobs = batch.exportJobs
    #expect(jobs.map(\.originalName) == ["a.jpg", "b.jpg", "c.jpg"])
    #expect(jobs.map(\.source) == batch.photos.map(\.source.url))
    #expect(jobs.map(\.placements) == batch.photos.map(\.placements))
}
