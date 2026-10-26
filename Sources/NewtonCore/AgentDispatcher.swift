import Foundation

public enum AgentPhase: String, Sendable, Equatable { case preparing, running, verifying, completed, failed, cancelled }
public struct AgentTaskStatus: Sendable, Equatable {
    public let runID: UUID
    public let phase: AgentPhase
    public var isRunning: Bool { [.preparing, .running, .verifying].contains(phase) }
    public let taskTitle: String
    public let latestOutput: String
    public let exitCode: Int32?
    public let passedTests: Bool?
    public let baseRevision: String?
    public let worktreePath: String?
    public let truncated: Bool
    public init(isRunning: Bool = false, taskTitle: String, latestOutput: String = "", exitCode: Int32? = nil, passedTests: Bool? = nil,
                runID: UUID = UUID(), phase: AgentPhase? = nil, baseRevision: String? = nil, worktreePath: String? = nil, truncated: Bool = false) {
        self.runID = runID; self.phase = phase ?? (isRunning ? .running : (passedTests == true ? .completed : .failed))
        self.taskTitle = taskTitle; self.latestOutput = latestOutput; self.exitCode = exitCode; self.passedTests = passedTests
        self.baseRevision = baseRevision; self.worktreePath = worktreePath; self.truncated = truncated
    }
}
public protocol ManualAgentRunning: Sendable {
    func run(id: UUID, task: PromptTask, repository: URL, provider: AIModelProvider, unattended: Bool,
             progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus
    func cancel(id: UUID) async
}
public actor AgentDispatcher: ManualAgentRunning, QueuedAgentRunning {
    public static let shared = AgentDispatcher()
    private let resolveExecutable: @Sendable (AIModelProvider) throws -> String
    private let worktreesDirectory: URL
    private let agentTimeout: TimeInterval
    private let verificationTimeout: TimeInterval
    private var activeID: UUID?
    private var operation: Task<AgentTaskStatus, Never>?
    public init(worktreesDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newton/AgentWorktrees"),
                agentTimeout: TimeInterval = 1800, verificationTimeout: TimeInterval = 600,
                resolveExecutable: @escaping @Sendable (AIModelProvider) throws -> String = { try AgentDispatcher.findExecutable($0.executableName) }) {
        self.worktreesDirectory = worktreesDirectory; self.resolveExecutable = resolveExecutable
        self.agentTimeout = agentTimeout; self.verificationTimeout = verificationTimeout
    }
    public static func findExecutable(_ name: String, path: String = ProcessInfo.processInfo.environment["PATH"] ?? "") throws -> String {
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let url = URL(fileURLWithPath: String(directory)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url.path }
        }
        throw StoreError(message: "\(name) not found in PATH. Configure the manual runner executable.")
    }
    public func run(id: UUID, task: PromptTask, repository: URL, provider: AIModelProvider = .codex, unattended: Bool = false,
                    progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        guard provider != .dualOrchestrated else { return AgentTaskStatus(taskTitle: task.title, latestOutput: "Dual orchestration is unavailable. Select Codex or Gemini.", runID: id, phase: .failed) }
        guard !unattended else { return AgentTaskStatus(taskTitle: task.title, latestOutput: "Unattended execution is disabled. Start a manual run in Newton.", runID: id, phase: .failed) }
        return await runOwned(id: id, task: task, repository: repository, provider: provider, completion: nil, progress: progress)
    }
    public func runApprovedQueueJob(id: UUID, task: PromptTask, permit: AutonomousRunPermit, progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        await runOwned(id: id, task: task, repository: permit.repository, provider: .codex, completion: permit.completion, progress: progress)
    }
    private func runOwned(id: UUID, task: PromptTask, repository: URL, provider: AIModelProvider, completion: CompletionCheck?, progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        guard activeID == nil else { return AgentTaskStatus(taskTitle: task.title, latestOutput: "Another manual run owns this runner", runID: id, phase: .failed) }
        activeID = id
        let operation = Task { await self.execute(id: id, task: task, repository: repository, provider: provider, completion: completion, progress: progress) }
        self.operation = operation
        var result = await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
        if result.phase != .completed, let path = result.worktreePath, FileManager.default.fileExists(atPath: path) {
            do {
                let receipt: [String: String] = ["runID": id.uuidString, "phase": result.phase.rawValue,
                    "baseRevision": result.baseRevision ?? "", "worktree": path, "outputTail": result.latestOutput]
                let data = try JSONEncoder().encode(receipt)
                let url = worktreesDirectory.appendingPathComponent(id.uuidString + ".json")
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                result = AgentTaskStatus(taskTitle: result.taskTitle, latestOutput: Self.tail(result.latestOutput + "\nLocal failure receipt could not be saved: \(error)"),
                    exitCode: result.exitCode, passedTests: result.passedTests, runID: id, phase: result.phase,
                    baseRevision: result.baseRevision, worktreePath: result.worktreePath, truncated: result.truncated)
            }
        }
        self.operation = nil; activeID = nil
        return result
    }
    public func cancel(id: UUID) { if activeID == id { operation?.cancel() } }
    private func execute(id: UUID, task: PromptTask, repository: URL, provider: AIModelProvider, completion: CompletionCheck?, progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        let runner = ProcessRunner(), worktree = worktreesDirectory.appendingPathComponent(id.uuidString)
        var revision: String?, output = "", truncated = false
        func state(_ phase: AgentPhase, _ text: String, code: Int32? = nil) -> AgentTaskStatus {
            AgentTaskStatus(taskTitle: task.title, latestOutput: Self.tail(text), exitCode: code, passedTests: phase == .completed ? true : nil,
                            runID: id, phase: phase, baseRevision: revision, worktreePath: worktree.path, truncated: truncated || text.utf8.count > 1_048_576)
        }
        func git(_ args: [String], at directory: URL) async throws -> ProcessResult {
            let result = try await runner.run("/usr/bin/git", args, directory: directory)
            guard result.exitCode == 0, !result.truncated else { throw StoreError(message: "Git operation failed: \(result.stderr)") }
            return result
        }
        do {
            try Task.checkCancellation()
            progress(state(.preparing, "Preparing isolated worktree from committed HEAD; uncommitted edits are excluded."))
            let executable = try resolveExecutable(provider)
            let rootResult = try await git(["rev-parse", "--show-toplevel"], at: repository)
            let root = URL(fileURLWithPath: rootResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            let head = try await git(["rev-parse", "--verify", "HEAD"], at: root)
            revision = head.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            try FileManager.default.createDirectory(at: worktreesDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Task.checkCancellation()
            _ = try await git(["worktree", "add", "--detach", worktree.path, revision!], at: root)
            try Task.checkCancellation()
            // No automatic merge or push. Only the dedicated checkout is supplied to the child.
            let base = revision!
            progress(state(.running, "Base \(base); worktree \(worktree.path). Source checkout uncommitted edits excluded."))
            let context = PromptGenerator.loadProjectContext(from: worktree)
            let grounded = PromptTask(title: task.title, objective: task.objective, targetFiles: task.targetFiles,
                fileSnippets: task.fileSnippets, architecturalContext: context)
            let prompt = PromptGenerator.generatePrompt(for: grounded)
            let arguments = completion == nil ? [provider == .codex ? "exec" : "-p", prompt] : ["exec","--sandbox","workspace-write","-c","approval_policy=\"never\"","-c","sandbox_workspace_write.network_access=false",prompt]
            let result = try await runner.run(executable, arguments, directory: worktree, timeout: completion == nil ? agentTimeout : min(1200, agentTimeout)) { text, cut in
                progress(AgentTaskStatus(taskTitle: task.title, latestOutput: text, runID: id, phase: .running,
                                         baseRevision: base, worktreePath: worktree.path, truncated: cut))
            }
            output = Self.tail(result.stdout + result.stderr); truncated = result.truncated || (result.stdout.utf8.count + result.stderr.utf8.count > 1_048_576)
            guard result.exitCode == 0 else { return state(.failed, output, code: result.exitCode) }
            try Task.checkCancellation()
            progress(state(.verifying, output + "\nRunning ./test.sh in isolated worktree"))
            let verificationStarted = ProcessInfo.processInfo.systemUptime
            let verificationBudget = completion == nil ? verificationTimeout : min(900, verificationTimeout)
            let prefix = output, previousCut = truncated
            let tests = try await runner.run("/bin/bash", ["./test.sh"], directory: worktree, timeout: verificationBudget) { text, cut in
                let combined = prefix + "\n" + text
                progress(AgentTaskStatus(taskTitle: task.title, latestOutput: Self.tail(combined), runID: id, phase: .verifying,
                                         baseRevision: base, worktreePath: worktree.path, truncated: previousCut || cut || combined.utf8.count > 1_048_576))
            }
            let combined = output + "\n" + tests.stdout + tests.stderr
            output = Self.tail(combined); truncated = truncated || tests.truncated || combined.utf8.count > 1_048_576
            guard tests.exitCode == 0 else { return state(.failed, output, code: tests.exitCode) }
            if let completion {
                let remaining = verificationBudget - (ProcessInfo.processInfo.systemUptime - verificationStarted)
                guard remaining > 0 else { throw StoreError(message: "Verification budget exhausted") }
                let build = try await runner.run("/bin/bash", ["./build.sh"], directory: worktree, timeout: remaining)
                output = Self.tail(output + "\n" + build.stdout + build.stderr)
                guard build.exitCode == 0, !build.truncated else { return state(.failed, output, code: build.exitCode) }
                try completion.validate(in: worktree)
                output += "\nTests, production build and explicit completion criterion passed. Retained for review; no merge or push."
            }
            try Task.checkCancellation()
            let status = try await git(["status", "--porcelain", "-z"], at: worktree)
            let current = try await git(["rev-parse", "HEAD"], at: worktree)
            if status.stdout.isEmpty && current.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == base {
                _ = try await git(["worktree", "remove", worktree.path], at: root)
            } // Changed/committed work and all failures remain available for review.
            try Task.checkCancellation()
            return state(.completed, output, code: 0)
        } catch let error as RunnerError {
            switch error {
            case .cancelled(let last), .timedOut(let last):
                let combined = output + "\n" + last.stdout + last.stderr
                truncated = truncated || last.truncated || combined.utf8.count > 1_048_576
                if case .cancelled = error { return state(.cancelled, Self.tail(combined) + "\nCancelled; prepared worktree retained.") }
                return state(.failed, Self.tail(combined) + "\nProcess deadline exceeded; prepared worktree retained.")
            case .launch(let code): return state(.failed, output + "\nFailed to launch process (POSIX \(code)); prepared worktree retained.")
            }
        } catch is CancellationError { return state(.cancelled, Self.tail(output + "\nCancelled; any prepared worktree retained for review.")) }
        catch { return state(.failed, Self.tail(output + "\n\(error) · any prepared worktree retained for review.")) }
    }
    public static func tail(_ text: String) -> String {
        var value = String(decoding: Data(text.utf8).suffix(1_048_576), as: UTF8.self)
        while value.utf8.count > 1_048_576 { value.removeFirst() }
        return value
    }
}
