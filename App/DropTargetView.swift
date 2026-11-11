import AppKit
import Face2EmojiCore
import SwiftUI

/// Transparent AppKit view covering the window. Accepts file promises (Apple Photos) and file URLs (Finder).
/// Promised files are received into a per-launch temp folder; Finder files are used in place.
/// Calls `onDrop` once per drag with sources in drag order; `originalName` is the file's last path component.
///
/// Mouse events pass through it to the views underneath: only dragging reaches it. A promised file
/// that fails to arrive is left out of the sources.
struct DropTargetView: NSViewRepresentable {
    var onDrop: ([PhotoSource]) -> Void

    /// Holds a fresh subfolder per drag, so that each promised file keeps the name its source gave it.
    /// Delete it when the app quits; not before, as the photos are read from it until then.
    static let promisedFilesFolder = FileManager.default.temporaryDirectory
        .appending(path: "face2emoji-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    func makeNSView(context: Context) -> DropView {
        DropView(onDrop: onDrop)
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.onDrop = onDrop
    }

    final class DropView: NSView {
        var onDrop: ([PhotoSource]) -> Void
        /// Promised files are read on it: the promise's source may still be writing a file when its
        /// read starts, and that read waits for the write to finish.
        private let promiseQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()

        /// Each dragged item becomes the first of these it can be read as: a promise wins over a file
        /// URL, so a source that offers both hands over the file under the name it chooses.
        private static let readableClasses: [AnyClass] = [NSFilePromiseReceiver.self, NSURL.self]
        private static let searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

        init(onDrop: @escaping ([PhotoSource]) -> Void) {
            self.onDrop = onDrop
            super.init(frame: .zero)
            let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
            registerForDraggedTypes(promiseTypes + [.fileURL])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used from a nib") }

        /// Invisible to mouse events. AppKit finds drag destinations by their registered types, not
        /// through `hitTest`, so drags still arrive.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            let readable = sender.draggingPasteboard.canReadObject(forClasses: Self.readableClasses, options: Self.searchOptions)
            guard readable else { return [] }
            // The files are copied (promises) or read in place (Finder), never moved.
            let allowed = sender.draggingSourceOperationMask
            return allowed.contains(.copy) ? .copy : allowed.intersection(.generic)
        }

        /// File promises can be called in only from here, so every one is called in before this returns.
        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            let drop = PendingDrop(onDrop: onDrop)
            let queue = promiseQueue
            var destination: URL?
            sender.enumerateDraggingItems(
                options: [], for: self, classes: Self.readableClasses, searchOptions: Self.searchOptions
            ) { draggingItem, _, _ in
                switch draggingItem.item {
                case let receiver as NSFilePromiseReceiver:
                    // Every promise of a drag must go to the same folder. Should creating it fail, the
                    // promised files fail to arrive and are left out.
                    let folder = destination ?? Self.makeDragFolder()
                    destination = folder
                    // `fileTypes` has one entry per promised file (one, for each item Photos promises).
                    // Some legacy sources list a type once for several files; files beyond the count
                    // are left out.
                    let slot = drop.addPromise(of: max(1, receiver.fileTypes.count), from: receiver)
                    receiver.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                        let source = error == nil ? PhotoSource(url: url, originalName: url.lastPathComponent) : nil
                        Task { @MainActor in drop.receive(source, in: slot) }
                    }
                case let url as URL:
                    drop.addFile(PhotoSource(url: url, originalName: url.lastPathComponent))
                default:
                    break
                }
            }
            return drop.finishAdding()
        }

        private static func makeDragFolder() -> URL {
            let folder = DropTargetView.promisedFilesFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }
}

/// One drag's sources, gathered as its promised files arrive and handed over together, in drag order,
/// once none is outstanding.
@MainActor
private final class PendingDrop {
    /// One per dragged item, in drag order.
    private struct Slot {
        var sources: [PhotoSource] = []
        /// Promised files that have neither arrived nor failed.
        var outstanding = 0
    }

    private let onDrop: ([PhotoSource]) -> Void
    private var slots: [Slot] = []
    /// Kept until the drop is handed over, in case a receiver must outlive its promises.
    private var receivers: [NSFilePromiseReceiver] = []
    private var isAdding = true
    private var isDelivered = false

    init(onDrop: @escaping ([PhotoSource]) -> Void) {
        self.onDrop = onDrop
    }

    func addFile(_ source: PhotoSource) {
        slots.append(Slot(sources: [source]))
    }

    /// Returns the slot to pass to `receive` for each of the promise's files.
    func addPromise(of fileCount: Int, from receiver: NSFilePromiseReceiver) -> Int {
        receivers.append(receiver)
        slots.append(Slot(outstanding: fileCount))
        return slots.count - 1
    }

    /// One promised file of `slot` arrived (`source`) or failed (nil). Files beyond those expected are
    /// left out, as is any file arriving after the drop was handed over.
    func receive(_ source: PhotoSource?, in slot: Int) {
        guard !isDelivered, slots[slot].outstanding > 0 else { return }
        slots[slot].outstanding -= 1
        if let source { slots[slot].sources.append(source) }
        deliverIfComplete()
    }

    /// Call once every dragged item has been added. Returns whether there was any.
    func finishAdding() -> Bool {
        isAdding = false
        deliverIfComplete()
        return !slots.isEmpty
    }

    private func deliverIfComplete() {
        guard !isAdding, !isDelivered, !slots.isEmpty, slots.allSatisfy({ $0.outstanding == 0 }) else { return }
        isDelivered = true
        receivers = []
        onDrop(slots.flatMap(\.sources))
    }
}
