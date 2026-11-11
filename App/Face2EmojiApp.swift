import AppKit
import Face2EmojiCore
import SwiftUI

@main
struct Face2EmojiApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var batch = Batch()

    var body: some Scene {
        // A single window: no File > New Window.
        Window("Face2Emoji", id: "main") {
            ContentView()
                .modifier(UndoManagerLink(batch: batch))
                .environment(batch)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}

/// Makes the batch's edits undoable through the window's undo manager, which Edit > Undo uses.
private struct UndoManagerLink: ViewModifier {
    let batch: Batch
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        content.onChange(of: undoManager, initial: true) { batch.undoManager = undoManager }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the one window quits the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: DropTargetView.promisedFilesFolder)
    }
}
