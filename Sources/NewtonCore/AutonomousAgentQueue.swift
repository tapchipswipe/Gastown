import Foundation

public struct CompletionCheck: Codable, Sendable, Equatable {
    public let description: String
    public let relativePath: String
    public let requiredText: String
    public init(description: String, relativePath: String, requiredText: String) { self.description = description; self.relativePath = relativePath; self.requiredText = requiredText }
    public func validate(in root: URL) throws {
        guard !description.isEmpty, !requiredText.isEmpty, requiredText.utf8.count <= 4000,
              !relativePath.hasPrefix("/"), !relativePath.split(separator: "/").contains("..") else { throw StoreError(message: "Invalid completion criterion") }
        let url = root.appendingPathComponent(relativePath).resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_000_000,
              try String(contentsOf: url, encoding: .utf8).contains(requiredText) else { throw StoreError(message: "Explicit completion criterion failed: " + description) }
    }
}
public struct TrustedBacklogItem: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let objective: String
    public let completion: CompletionCheck
    public init(id: String, title: String, objective: String, completion: CompletionCheck) { self.id = id; self.title = title; self.objective = objective; self.completion = completion }
}
public struct AutonomousEnvironment: Sendable {
    public let now: Date
    public let unlocked: Bool
    public let externallyPowered: Bool
    public let acceptableThermalState: Bool
    public let idleSeconds: Double
    public let quota: CodexQuota?
    public init(now: Date, unlocked: Bool, externallyPowered: Bool, acceptableThermalState: Bool, idleSeconds: Double, quota: CodexQuota?) {
        self.now = now; self.unlocked = unlocked; self.externallyPowered = externallyPowered; self.acceptableThermalState = acceptableThermalState; self.idleSeconds = idleSeconds; self.quota = quota
    }
    public func executionDenial(calendar: Calendar = .current) -> String? {
        let hour = calendar.component(.hour, from: now)
        if hour < 22 && hour >= 8 { return "Outside 22:00–08:00 execution window" }
        if !unlocked { return "Locked, sleeping or Pause All" }
        if !externallyPowered { return "External power required" }
        if !acceptableThermalState { return "Thermal state elevated or unavailable" }
        return nil
    }
    public func denial(calendar: Calendar = .current) -> String? {
        if let denial = executionDenial(calendar: calendar) { return denial }
        guard unlocked else { return "Locked, sleeping or Pause All" }
        guard externallyPowered else { return "External power required" }
        guard acceptableThermalState else { return "Thermal state elevated or unavailable" }
        guard idleSeconds.isFinite, idleSeconds >= 120 else { return "User active; admission paused" }
        guard let quota, now.timeIntervalSince(quota.observedAt) >= -60, now.timeIntervalSince(quota.observedAt) <= 900 else { return "Quota unknown, stale or invalid" }
        let windows = [quota.primary] + (quota.secondary.map { [$0] } ?? [])
        guard windows.allSatisfy({ $0.usedPercent.isFinite && $0.usedPercent >= 0 && $0.usedPercent < 30 && !$0.isExpired(at: now) }) else { return "Quota usage must be below 30% in every known window" }
        return nil
    }
    public func nightID(calendar: Calendar = .current) -> String {
        let day = calendar.component(.hour, from: now) < 8 ? calendar.date(byAdding: .day, value: -1, to: now)! : now
        let parts = calendar.dateComponents([.year,.month,.day], from: day)
        return "\(parts.year!)-\(parts.month!)-\(parts.day!)"
    }
}
public struct AutonomousJob: Codable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case queued, running, verifying, verified, failed, interruptedReview }
    public let id: String
    public let item: TrustedBacklogItem
    public var state: State
    public var night: String?
    public var admittedAt: Date?
    public var finishedAt: Date?
    public var evidence: String
    public var worktree: String?
}
/// Only a queue can construct this permit after durable admission and policy checks.
public struct AutonomousRunPermit: Sendable {
    let repository: URL
    let completion: CompletionCheck
    init(repository: URL, completion: CompletionCheck) { self.repository = repository; self.completion = completion }
}
public protocol QueuedAgentRunning: Sendable {
    func runApprovedQueueJob(id: UUID, task: PromptTask, permit: AutonomousRunPermit, progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus
    func cancel(id: UUID) async
}

public actor AutonomousAgentQueue {
    private let store: IntelligenceStore
    private let runner: any QueuedAgentRunning
    private let repository: URL
    private var admitting = false
    private var operation: Task<Void, Never>?
    private var runID: UUID?
    private var generation = UUID()
    public init(store: IntelligenceStore, repository: URL, runner: any QueuedAgentRunning = AgentDispatcher.shared) {
        self.store = store; self.repository = repository.resolvingSymlinksInPath(); self.runner = runner
    }
    public func recoverInterrupted() async throws {
        for var job in try await store.list(AutonomousJob.self, namespace: "jobs") where [.running,.verifying].contains(job.state) {
            job.state = .interruptedReview; job.evidence += "\nPrevious process interrupted; manual review required. No automatic replay."
            try await store.save(job, namespace: "jobs", id: job.id)
        }
    }
    /// Reads only committed structured Newton backlog. No API accepts Mail/OCR/transcript text.
    public func ingestCommittedBacklog() async throws {
        let git = ProcessRunner()
        let root = try await git.run("/usr/bin/git", ["rev-parse","--show-toplevel"], directory: repository)
        guard root.exitCode == 0, URL(fileURLWithPath: root.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).resolvingSymlinksInPath() == repository else { throw StoreError(message: "Queue repository must be the configured Newton root") }
        let result = try await git.run("/usr/bin/git", ["show","HEAD:Automation/backlog.json"], directory: repository, outputLimit: 128_000)
        guard result.exitCode == 0, !result.truncated else { throw StoreError(message: "No bounded committed Newton backlog available") }
        let items = try JSONDecoder().decode([TrustedBacklogItem].self, from: Data(result.stdout.utf8))
        guard items.count <= 100 else { throw StoreError(message: "Backlog exceeds 100 items") }
        for item in items {
            guard !item.id.isEmpty, !item.title.isEmpty, !item.objective.isEmpty, !item.completion.description.isEmpty,
                  !item.completion.relativePath.isEmpty, !item.completion.requiredText.isEmpty else { throw StoreError(message: "Every trusted job requires an explicit completion criterion") }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let id = ReceiptParser.digest(String(decoding: try encoder.encode(item), as: UTF8.self))
            if try await store.load(AutonomousJob.self, namespace: "jobs", id: id) == nil {
                try await store.save(AutonomousJob(id: id, item: item, state: .queued, evidence: "Committed Newton backlog item: " + item.id), namespace: "jobs", id: id)
            }
        }
    }
    public func ingestReproducibleDiagnostics() async throws {
        guard let diagnostic = try await NewtonDiagnostics.reproduce(repository: repository,store: store) else { return }
        let title = "Repair reproducible Newton regressions: " + diagnostic.failureNames.joined(separator: ", ")
        let item = TrustedBacklogItem(id: "diagnostic:" + diagnostic.revision,title: title,objective: title + ". Reproduce with ./test.sh, fix the committed Newton code, retain the regression runner and pass all tests plus the production build.",completion: CompletionCheck(description: "Full test suite and production build pass; committed Swift test runner remains present",relativePath: "test.sh",requiredText: "swift test"))
        let id = ReceiptParser.digest(item.id)
        if try await store.load(AutonomousJob.self,namespace: "jobs",id: id) == nil {
            try await store.save(AutonomousJob(id: id,item: item,state: .queued,evidence: "Two owned test runs reproduced stable identifiers at " + diagnostic.revision),namespace: "jobs",id: id)
        }
    }
    public func jobs() async throws -> [AutonomousJob] { try await store.list(AutonomousJob.self, namespace: "jobs") }
    public func tick(_ environment: AutonomousEnvironment, calendar: Calendar = .current) async throws -> String {
        guard operation == nil,!admitting else { return "One owned job is already running or being admitted" }
        admitting = true; defer { admitting = false }
        let admissionGeneration = generation
        if let denial = environment.denial(calendar: calendar) { return denial }
        var jobs = try await jobs()
        let night = environment.nightID(calendar: calendar)
        guard jobs.filter({ $0.night == night }).count < 2 else { return "Two-job nightly admission limit reached" }
        if jobs.contains(where: { $0.state == .queued }) == false {
            try await ingestReproducibleDiagnostics(); jobs = try await self.jobs()
        }
        guard var job = jobs.first(where: { $0.state == .queued }) else { return "No trusted queued work" }
        guard !Task.isCancelled,generation == admissionGeneration else { return "Admission cancelled" }
        job.state = .running; job.night = night; job.admittedAt = environment.now
        try await store.save(job, namespace: "jobs", id: job.id)
        guard !Task.isCancelled,generation == admissionGeneration else {
            job.state = .interruptedReview; job.evidence += "\nAdmission interrupted; review required"
            try await store.save(job,namespace: "jobs",id: job.id); return "Admission cancelled"
        }
        let id = UUID(), epoch = generation; runID = id
        let item = job.item, root = repository, runner = runner, persistence = store, selectedID = job.id
        operation = Task { [weak self] in
            let result = await runner.runApprovedQueueJob(id: id,
                task: PromptTask(title: item.title, objective: item.objective + "\nCompletion criterion: " + item.completion.description),
                permit: AutonomousRunPermit(repository: root, completion: item.completion), progress: { status in
                    if status.phase == .preparing || status.phase == .verifying {
                        Task { try? await persistence.recordJobProgress(id: selectedID,phase: status.phase,evidence: status.latestOutput,worktree: status.worktreePath) }
                    }
                })
            await self?.finish(jobID: job.id, result: result, generation: epoch)
        }
        return "Admitted trusted job; quota snapshot is not a morning-capacity guarantee"
    }
    private func finish(jobID: String, result: AgentTaskStatus, generation: UUID) async {
        defer { operation = nil; runID = nil }
        do {
            guard var job = try await store.load(AutonomousJob.self, namespace: "jobs", id: jobID) else { return }
            job.state = result.phase == .completed && result.passedTests == true && generation == self.generation ? .verified : (result.phase == .cancelled || generation != self.generation ? .interruptedReview : .failed)
            job.finishedAt = Date(); job.evidence = String(result.latestOutput.suffix(40_000)); job.worktree = result.worktreePath
            try await store.save(job, namespace: "jobs", id: job.id)
        } catch { /* The durable running record becomes interruptedReview on next startup. */ }
    }
    public var isRunning: Bool { operation != nil }
    public func waitUntilIdle() async { await operation?.value }
    public func cancel() async {
        generation = UUID(); operation?.cancel()
        if let runID { await runner.cancel(id: runID) }
        await operation?.value
    }
}
