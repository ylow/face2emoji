import Foundation
import Testing
import Face2EmojiCore

@Test func writesAllWithUniqueNamesAndReportsFailures() async throws {
    let folder = try makeTempFolder()
    let good = try TestImages.writeJPEG(width: 10, height: 10)
    let bad = tempURL("bad.jpg"); try Data("nope".utf8).write(to: bad)
    let jobs = [ExportJob(source: good, originalName: "IMG_1.HEIC", placements: []),
                ExportJob(source: bad,  originalName: "broken.jpg", placements: []),
                ExportJob(source: good, originalName: "IMG_1.jpg",  placements: [])]
    var ticks: [Int] = []
    let report = await BatchExporter.export(jobs, to: folder) { ticks.append($0) }
    #expect(report == ExportReport(written: 2, failed: ["broken.jpg"], cancelled: false))
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["IMG_1.jpg", "IMG_1 2.jpg"])
    #expect(ticks.sorted() == [1, 2, 3])
}
@Test func unwritableFolderFailsEveryJobWithoutThrowing() async throws {
    let good = try TestImages.writeJPEG(width: 10, height: 10)
    let report = await BatchExporter.export([ExportJob(source: good, originalName: "a.jpg", placements: [])],
                                            to: URL(filePath: "/nonexistent-\(UUID())")) { _ in }
    #expect(report == ExportReport(written: 0, failed: ["a.jpg"], cancelled: false))
}
@Test func cancellationStopsEarlyAndKeepsWrittenFiles() async throws {
    let folder = try makeTempFolder()
    let src = TestImages.fixture("one-face.jpg")
    let jobs = (0..<40).map { ExportJob(source: src, originalName: "p\($0).jpg", placements: []) }
    let task = Task { await BatchExporter.export(jobs, to: folder) { _ in } }
    try await Task.sleep(for: .milliseconds(30)); task.cancel()
    let report = await task.value
    #expect(report.cancelled && report.written < 40)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == report.written)
}
