import Foundation

/// One photo to export.
public struct ExportJob: Sendable {
    public var source: URL
    /// The photo's file name as the user knows it; the output is named after it.
    public var originalName: String
    public var placements: [EmojiPlacement]

    public init(source: URL, originalName: String, placements: [EmojiPlacement]) {
        self.source = source
        self.originalName = originalName
        self.placements = placements
    }
}

/// The outcome of a batch export.
public struct ExportReport: Equatable, Sendable {
    public var written: Int
    /// Original names of the jobs that failed, in job order.
    public var failed: [String]
    /// The export was cancelled before every job had started; jobs not started are neither
    /// written nor failed.
    public var cancelled: Bool

    public init(written: Int, failed: [String], cancelled: Bool) {
        self.written = written
        self.failed = failed
        self.cancelled = cancelled
    }
}

/// Exports a batch of photos into one folder.
public enum BatchExporter {
    private static let maxConcurrentJobs = 4

    /// Up to 4 jobs at a time. Names are assigned up front, in job order, so the result is deterministic.
    /// `progress` is called on the main actor with the number of jobs finished so far (success or failure).
    /// Cancelling the calling task stops starting new jobs; files already written stay.
    public static func export(_ jobs: [ExportJob], to folder: URL,
                              progress: @MainActor @Sendable (Int) -> Void) async -> ExportReport {
        var taken = Set<String>()
        let destinations = jobs.map { job in
            folder.appending(path: ExportNaming.uniqueName(
                ExportNaming.outputName(forOriginal: job.originalName), in: folder, taken: &taken
            ))
        }
        var succeeded = [Bool?](repeating: nil, count: jobs.count)   // nil: never started
        await withTaskGroup(of: (index: Int, succeeded: Bool).self) { group in
            var next = 0
            func startNextJob() {
                guard next < jobs.count else { return }
                let index = next, job = jobs[index], destination = destinations[index]
                let started = group.addTaskUnlessCancelled {
                    do {
                        try Exporter.export(source: job.source, placements: job.placements, to: destination)
                        return (index, true)
                    } catch {
                        return (index, false)
                    }
                }
                if started { next += 1 }
            }
            for _ in 0..<maxConcurrentJobs { startNextJob() }
            var finished = 0
            while let result = await group.next() {
                succeeded[result.index] = result.succeeded
                startNextJob()
                finished += 1
                await progress(finished)
            }
        }
        return ExportReport(
            written: succeeded.count { $0 == true },
            failed: zip(jobs, succeeded).filter { $0.1 == false }.map(\.0.originalName),
            cancelled: succeeded.contains(nil)
        )
    }
}
