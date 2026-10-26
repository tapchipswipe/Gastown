import Foundation

public enum FileIntakeRequest: Sendable {
    case ideas(URL)
    case timeAtlas(URL)
    case saveIdea(title: String, detail: String, directory: URL, existing: URL?)
}
public struct FileIntakeResult: Sendable {
    public let report: IntakeReport
    public let savedURL: URL?
    public init(report: IntakeReport, savedURL: URL? = nil) { self.report = report; self.savedURL = savedURL }
}
public enum FileIntake {
    public static func load(_ request: FileIntakeRequest) async throws -> FileIntakeResult {
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            switch request {
            case .ideas(let directory): return FileIntakeResult(report: try iCloudIdeaStore.readReport(from: directory))
            case .timeAtlas(let directory): return FileIntakeResult(report: try TimeAtlasReader.readReport(from: directory))
            case let .saveIdea(title, detail, directory, existing):
                let url = try existing ?? iCloudIdeaStore.saveIdea(title: title, detail: detail, in: directory)
                var report = IntakeReport()
                do { report.events = try iCloudIdeaStore.readIdea(url) }
                catch { report.diagnostics = ["File saved, indexing input failed: \(error)"] }
                return FileIntakeResult(report: report, savedURL: url)
            }
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}
