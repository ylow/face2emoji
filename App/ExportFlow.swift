import AppKit
import Face2EmojiCore
import SwiftUI

/// Exporting the whole batch: choosing a folder, the export itself behind a progress sheet, then an
/// alert with the result. There is one export at a time, from the moment it starts until its result
/// has been dismissed.
@MainActor @Observable
final class ExportFlow {
    struct Progress {
        /// Photos finished, written or failed.
        var done = 0
        var total: Int
        /// Cancel was pressed; the photos already being written are finishing.
        var isCancelling = false
    }

    struct Outcome {
        var report: ExportReport
        var folder: URL

        var title: String {
            report.cancelled
                ? "Export cancelled — \(report.written) photo(s) written"
                : "Exported \(report.written) photo(s)"
        }

        /// nil when every photo started was written.
        var message: String? {
            report.failed.isEmpty ? nil : (["Could not export:"] + report.failed).joined(separator: "\n")
        }
    }

    /// An export is running; the progress sheet shows.
    private(set) var isExporting = false
    /// The latest export's progress. It is kept once that export has finished, so that the sheet
    /// does not go blank while it closes.
    private(set) var progress = Progress(total: 0)
    /// The finished export's result, shown until dismissed by setting it to nil.
    var outcome: Outcome?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// An export is running or its result is showing. The batch behind must not be acted on meanwhile.
    var isActive: Bool { isExporting || outcome != nil }

    /// Needs photos, every one of them loaded and scanned for faces, and no export already active.
    func canExport(_ batch: Batch) -> Bool {
        !isActive && !batch.isBusy && !batch.photos.isEmpty
    }

    /// Asks for a folder, in a panel that blocks the app until it closes, then exports `batch`
    /// into it; see `export(_:to:)`.
    func chooseFolderAndExport(_ batch: Batch) {
        guard canExport(batch) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        export(batch, to: folder)
    }

    /// Writes every photo of `batch` into `folder`, with its emoji as they are at this call: edits
    /// made later do not reach this export. Shows the progress sheet until the export has finished,
    /// then the result. Cancelling stops photos from being started; those already written stay.
    /// Does nothing unless `canExport(batch)`.
    func export(_ batch: Batch, to folder: URL) {
        guard canExport(batch) else { return }
        let jobs = batch.exportJobs
        progress = Progress(total: jobs.count)
        isExporting = true
        task = Task {
            let report = await BatchExporter.export(jobs, to: folder) { done in self.progress.done = done }
            isExporting = false
            outcome = Outcome(report: report, folder: folder)
        }
    }

    func cancel() {
        guard isExporting else { return }
        task?.cancel()
        progress.isCancelling = true
    }
}

extension View {
    /// Shows `flow`'s progress sheet while it exports, then its result alert.
    func exportFlow(_ flow: ExportFlow) -> some View {
        modifier(ExportFlowPresenter(flow: flow))
    }
}

private struct ExportFlowPresenter: ViewModifier {
    let flow: ExportFlow

    func body(content: Content) -> some View {
        content
            // The sheet closes only when the export has finished.
            .sheet(isPresented: Binding(get: { flow.isExporting }, set: { _ in })) {
                ExportProgressView(flow: flow)
                    .interactiveDismissDisabled()
            }
            .alert(flow.outcome?.title ?? "", isPresented: isShowingOutcome, presenting: flow.outcome) { outcome in
                // The first button is the default one, which Return presses.
                Button("OK") {}
                Button("Show in Finder") { NSWorkspace.shared.open(outcome.folder) }
            } message: { outcome in
                if let message = outcome.message { Text(message) }
            }
    }

    private var isShowingOutcome: Binding<Bool> {
        Binding(get: { flow.outcome != nil }, set: { if !$0 { flow.outcome = nil } })
    }
}

private struct ExportProgressView: View {
    let flow: ExportFlow

    var body: some View {
        let progress = flow.progress
        VStack(alignment: .leading, spacing: 12) {
            Text("Exporting \(progress.done) of \(progress.total)…")
                .monospacedDigit()
            ProgressView(value: Double(progress.done), total: Double(progress.total))
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { flow.cancel() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(progress.isCancelling)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
