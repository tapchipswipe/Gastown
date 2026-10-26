import Foundation

public struct ReproducedDiagnostic: Codable, Sendable {
    public let revision: String
    public let failureNames: [String]
    public let firstExitCode: Int32
    public let secondExitCode: Int32
    public let observedAt: Date
    public let worktree: String
}
/// Executes only the committed Newton test runner, twice in a disposable HEAD worktree.
/// Only stable test identifiers authorize a repair; arbitrary diagnostic prose is not a prompt.
public enum NewtonDiagnostics {
    public static func failureNames(_ text: String) -> [String] {
        let pattern = #"✘ Test ([A-Za-z_][A-Za-z0-9_]*)\("#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let source = text as NSString
        return Array(Set(regex.matches(in: text,range: NSRange(location: 0,length: source.length)).map { source.substring(with: $0.range(at: 1)) })).sorted()
    }
    public static func reproduce(repository: URL,store: IntelligenceStore) async throws -> ReproducedDiagnostic? {
        let runner = ProcessRunner()
        let head = try await runner.run("/usr/bin/git",["rev-parse","--verify","HEAD"],directory: repository)
        guard head.exitCode == 0,!head.truncated else { throw StoreError(message: "Diagnostic HEAD unavailable") }
        let revision = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if try await store.load(Bool.self,namespace: "diagnostic-revisions",id: revision) == true { return nil }
        try await store.save(true,namespace: "diagnostic-revisions",id: revision)
        let parent = FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("Newton/DiagnosticWorktrees")
        try FileManager.default.createDirectory(at: parent,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        let worktree = parent.appendingPathComponent(UUID().uuidString)
        let created = try await runner.run("/usr/bin/git",["worktree","add","--detach",worktree.path,revision],directory: repository)
        guard created.exitCode == 0 else { throw StoreError(message: "Diagnostic worktree unavailable") }
        func cleanup() async {
            let status = try? await runner.run("/usr/bin/git",["status","--porcelain"],directory: worktree)
            if status?.exitCode == 0 && status?.stdout.isEmpty == true {
                _ = try? await runner.run("/usr/bin/git",["worktree","remove",worktree.path],directory: repository)
            }
        }
        do {
            let first = try await runner.run("/bin/bash",["./test.sh"],directory: worktree,timeout: 300,outputLimit: 1_048_576)
            let names = failureNames(first.stdout + first.stderr)
            guard first.exitCode != 0,!first.truncated,!names.isEmpty else { await cleanup(); return nil }
            try Task.checkCancellation()
            let second = try await runner.run("/bin/bash",["./test.sh"],directory: worktree,timeout: 300,outputLimit: 1_048_576)
            guard second.exitCode != 0,!second.truncated,failureNames(second.stdout + second.stderr) == names else { await cleanup(); return nil }
            let evidence = ReproducedDiagnostic(revision: revision,failureNames: names,firstExitCode: first.exitCode,secondExitCode: second.exitCode,observedAt: Date(),worktree: worktree.path)
            try await store.save(evidence,namespace: "diagnostics",id: revision)
            await cleanup(); return evidence
        } catch { await cleanup(); throw error }
    }
}
