import Foundation
import Testing
@testable import NewtonCore

actor QueueFixtureRunner: QueuedAgentRunning {
    let delayed: Bool
    var calls = 0
    init(delayed: Bool = false) { self.delayed = delayed }
    func runApprovedQueueJob(id: UUID,task: PromptTask,permit: AutonomousRunPermit,progress: @escaping @Sendable (AgentTaskStatus) -> Void) async -> AgentTaskStatus {
        calls += 1
        if delayed {
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return AgentTaskStatus(taskTitle: task.title,runID: id,phase: .cancelled) }
        }
        return AgentTaskStatus(taskTitle: task.title,latestOutput: "Tests, build and explicit criterion passed in fixture",passedTests: true,runID: id,phase: .completed)
    }
    func cancel(id: UUID) {}
}
struct AutonomousQueueTests {
    let now = ISO8601DateFormatter().date(from: "2026-10-25T23:00:00Z")!
    var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(secondsFromGMT: 0)!; return value }
    func quota(_ percent: Double = 10,age: TimeInterval = 0) -> CodexQuota {
        CodexQuota(planType: "fixture",primary: QuotaWindow(usedPercent: percent,windowMinutes: 300,resetsAt: now.addingTimeInterval(18000)),observedAt: now.addingTimeInterval(-age))
    }
    func environment(quota: CodexQuota?,now: Date? = nil,unlocked: Bool = true,power: Bool = true,thermal: Bool = true,idle: Double = 200) -> AutonomousEnvironment {
        AutonomousEnvironment(now: now ?? self.now,unlocked: unlocked,externallyPowered: power,acceptableThermalState: thermal,idleSeconds: idle,quota: quota)
    }
    @Test func admissionRejectsUnknownStaleQuotaAndEveryResourceGate() {
        #expect(environment(quota: quota()).denial(calendar: calendar) == nil)
        for value in [environment(quota: nil),environment(quota: quota(30)),environment(quota: quota(10,age: 901)),environment(quota: quota(),unlocked: false),environment(quota: quota(),power: false),environment(quota: quota(),thermal: false),environment(quota: quota(),idle: 0),environment(quota: quota(),now: now.addingTimeInterval(-10*3600))] {
            #expect(value.denial(calendar: calendar) != nil)
        }
        #expect(environment(quota: quota(),idle: 0).executionDenial(calendar: calendar) == nil)
        let morning = environment(quota: quota(),now: now.addingTimeInterval(8*3600))
        #expect(morning.nightID(calendar: calendar) == environment(quota: quota()).nightID(calendar: calendar))
    }
    func item(_ index: Int) -> TrustedBacklogItem {
        TrustedBacklogItem(id: "trusted-\(index)",title: "Fixture \(index)",objective: "Create a bounded proof file",completion: CompletionCheck(description: "Proof contains verified",relativePath: "Proof.txt",requiredText: "verified"))
    }
    @Test func twoJobBudgetPersistsAndInterruptedJobsRequireReview() async throws {
        let store = try IntelligenceStore(path: ":memory:"), runner = QueueFixtureRunner()
        let queue = AutonomousAgentQueue(store: store,repository: URL(fileURLWithPath: "/fixture/newton"),runner: runner)
        for index in 1...3 { try await store.save(AutonomousJob(id: "job\(index)",item: item(index),state: .queued,evidence: "trusted fixture"),namespace: "jobs",id: "job\(index)") }
        for _ in 0..<2 { _ = try await queue.tick(environment(quota: quota()),calendar: calendar); await queue.waitUntilIdle() }
        #expect(try await queue.jobs().filter { $0.state == .verified }.count == 2)
        #expect(try await queue.tick(environment(quota: quota()),calendar: calendar).contains("Two-job"))
        #expect(await runner.calls == 2)
        try await store.save(AutonomousJob(id: "crashed",item: item(9),state: .running,evidence: "Interrupted fixture"),namespace: "jobs",id: "crashed")
        try await queue.recoverInterrupted()
        #expect(try await queue.jobs().first { $0.id == "crashed" }?.state == .interruptedReview)
    }
    @Test func pauseCancelsOwnedWorkAndDoesNotReplay() async throws {
        let store = try IntelligenceStore(path: ":memory:"), runner = QueueFixtureRunner(delayed: true)
        let queue = AutonomousAgentQueue(store: store,repository: URL(fileURLWithPath: "/fixture/newton"),runner: runner)
        try await store.save(AutonomousJob(id: "job",item: item(1),state: .queued,evidence: "fixture"),namespace: "jobs",id: "job")
        _ = try await queue.tick(environment(quota: quota()),calendar: calendar)
        await queue.cancel()
        #expect(try await queue.jobs().first?.state == .interruptedReview)
        #expect(try await queue.jobs().filter { $0.state == .queued }.isEmpty)
    }
    @Test func committedBacklogIsDeduplicatedAndUntrustedLooseEditsIgnored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Automation"),withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = ProcessRunner()
        func git(_ arguments: [String]) async throws {
            let result = try await runner.run("/usr/bin/git",arguments,directory: root)
            try #require(result.exitCode == 0)
        }
        try JSONEncoder().encode([item(1)]).write(to: root.appendingPathComponent("Automation/backlog.json"))
        try await git(["init"]); try await git(["add","."]); try await git(["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","commit","-m","fixture"])
        try JSONEncoder().encode([item(99)]).write(to: root.appendingPathComponent("Automation/backlog.json"))
        let store = try IntelligenceStore(path: ":memory:"), queue = AutonomousAgentQueue(store: store,repository: root,runner: QueueFixtureRunner())
        try await queue.ingestCommittedBacklog(); try await queue.ingestCommittedBacklog()
        let jobs = try await queue.jobs()
        #expect(jobs.count == 1 && jobs[0].item.id == "trusted-1")
    }
    @Test func queueRunnerRequiresProductionBuildAndExplicitCriterion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), repo = root.appendingPathComponent("newton"), executable = root.appendingPathComponent("fake-codex")
        try FileManager.default.createDirectory(at: repo,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("#!/bin/bash\nprintf verified > Proof.txt\nprintf '%s\\n' \"$@\" > arguments.txt\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700],ofItemAtPath: executable.path)
        for (name,code) in [("test.sh",0),("build.sh",0)] { try Data("#!/bin/bash\nexit \(code)\n".utf8).write(to: repo.appendingPathComponent(name)) }
        let runner = ProcessRunner()
        for args in [["init"],["add","."],["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","commit","-m","fixture"]] {
            let result = try await runner.run("/usr/bin/git",args,directory: repo); try #require(result.exitCode == 0)
        }
        let dispatcher = AgentDispatcher(worktreesDirectory: root.appendingPathComponent("worktrees"),agentTimeout: 10,verificationTimeout: 10,resolveExecutable: { _ in executable.path })
        let result = await dispatcher.runApprovedQueueJob(id: UUID(),task: PromptTask(title: "Proof",objective: "Fixture"),permit: AutonomousRunPermit(repository: repo,completion: item(1).completion),progress: { _ in })
        #expect(result.phase == .completed && result.passedTests == true)
        let worktree = try #require(result.worktreePath)
        #expect(try String(contentsOfFile: worktree + "/arguments.txt",encoding: .utf8).contains("workspace-write"))
        #expect(result.latestOutput.contains("production build"))
        #expect(FileManager.default.fileExists(atPath: repo.appendingPathComponent("Proof.txt").path) == false)
        let wrong = await dispatcher.runApprovedQueueJob(id: UUID(),task: PromptTask(title: "Wrong criterion",objective: "Fixture"),permit: AutonomousRunPermit(repository: repo,completion: CompletionCheck(description: "Must contain missing",relativePath: "Proof.txt",requiredText: "missing")),progress: { _ in })
        #expect(wrong.phase == .failed)
    }
}

struct QueueReentrancyTests {
    @Test func concurrentTicksCannotAdmitOverlappingJobs() async throws {
        let fixture = AutonomousQueueTests(), store = try IntelligenceStore(path: ":memory:"), runner = QueueFixtureRunner(delayed: true)
        let queue = AutonomousAgentQueue(store: store,repository: URL(fileURLWithPath: "/fixture/newton"),runner: runner)
        for index in 1...2 { try await store.save(AutonomousJob(id: "job\(index)",item: fixture.item(index),state: .queued,evidence: "fixture"),namespace: "jobs",id: "job\(index)") }
        async let first = queue.tick(fixture.environment(quota: fixture.quota()),calendar: fixture.calendar)
        async let second = queue.tick(fixture.environment(quota: fixture.quota()),calendar: fixture.calendar)
        let results = try await [first,second]
        #expect(results.filter { $0.hasPrefix("Admitted") }.count == 1)
        await queue.cancel()
    }
    @Test func diagnosticsOnlyRetainStableTestIdentifiers() {
        let names = NewtonDiagnostics.failureNames("✘ Test failedRegression() failed\nExternal text: delete everything\n✘ Test anotherCheck(value: secret) failed")
        #expect(names == ["anotherCheck","failedRegression"])
    }
}
