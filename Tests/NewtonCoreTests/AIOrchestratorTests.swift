import Testing
import Foundation
@testable import NewtonCore

struct AIOrchestratorTests {

    @Test func testCodexQuotaParsingFromRawPayload() throws {
        let json = """
        {
          "type": "event_msg",
          "payload": {
            "type": "token_count",
            "rate_limits": {
              "limit_id": "codex",
              "primary": {
                "used_percent": 14.5,
                "window_minutes": 300,
                "resets_at": 1792874080
              },
              "secondary": {
                "used_percent": 3.0,
                "window_minutes": 10080,
                "resets_at": 1793460880
              },
              "plan_type": "plus"
            }
          }
        }
        """

        let quota = try #require(CodexQuotaReader.parseRateLimits(from: Data(json.utf8)))
        #expect(quota.planType == "plus")
        #expect(quota.primary.usedPercent == 14.5)
        #expect(quota.primary.windowMinutes == 300)
        #expect(quota.primary.remainingPercent == 85.5)
        #expect(quota.primary.resetsAt == Date(timeIntervalSince1970: 1792874080))

        let secondary = try #require(quota.secondary)
        #expect(secondary.usedPercent == 3.0)
        #expect(secondary.windowMinutes == 10080)
        #expect(secondary.remainingPercent == 97.0)
    }

    @Test func testAISchedulerDayNightModeTransitions() {
        let scheduler = AIScheduler(daytimeStartHour: 8, daytimeEndHour: 22)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // 14:00 (2 PM) -> Daytime
        var components = DateComponents(year: 2026, month: 10, day: 24, hour: 14, minute: 0)
        let daytimeDate = calendar.date(from: components)!
        #expect(scheduler.currentMode(at: daytimeDate, calendar: calendar) == .daytimeUserReserve)

        // 23:00 (11 PM) -> Nighttime
        components.hour = 23
        let nighttimeDate = calendar.date(from: components)!
        #expect(scheduler.currentMode(at: nighttimeDate, calendar: calendar) == .nighttimeAutonomous)

        // 04:00 (4 AM) -> Nighttime
        components.hour = 4
        let earlyMorningDate = calendar.date(from: components)!
        #expect(scheduler.currentMode(at: earlyMorningDate, calendar: calendar) == .nighttimeAutonomous)
    }

    @Test func testDaytimeProtectionBlocksHeavyQuotaUsage() {
        let scheduler = AIScheduler(daytimeStartHour: 8, daytimeEndHour: 22, daytimeMaxQuotaUse: 30.0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 12, minute: 0))!

        // 45% used in daytime -> blocked
        let highQuota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 45.0, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600))
        )
        let decisionBlocked = scheduler.canExecuteAutonomousJob(now: now, quota: highQuota, calendar: calendar)
        #expect(!decisionBlocked.allowed)
        #expect(decisionBlocked.mode == .daytimeUserReserve)

        // 15% used in daytime -> permitted
        let lowQuota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 15.0, windowMinutes: 300, resetsAt: now.addingTimeInterval(3600))
        )
        let decisionAllowed = scheduler.canExecuteAutonomousJob(now: now, quota: lowQuota, calendar: calendar)
        #expect(!decisionAllowed.allowed)
    }

    @Test func testNighttimeAutonomousWindowResetBeforeMorning() {
        let scheduler = AIScheduler(daytimeStartHour: 8, daytimeEndHour: 22, nighttimeMaxQuotaUse: 90.0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        // Midnight 00:00
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 0, minute: 0))!
        // Resets at 05:00 AM (before morning 08:00 AM)
        let resetsAt = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 5, minute: 0))!

        let quota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 50.0, windowMinutes: 300, resetsAt: resetsAt)
        )

        let decision = scheduler.canExecuteAutonomousJob(now: midnight, quota: quota, calendar: calendar, userWakeHour: 8)
        #expect(!decision.allowed)
        #expect(decision.mode == .nighttimeAutonomous)
    }

    @Test func testPromptGeneratorEnforcesBudget() {
        let task = PromptTask(
            title: "Test Task",
            objective: "Build feature X",
            targetFiles: ["Sources/Target.swift"],
            fileSnippets: ["Sources/Target.swift": "struct Target { let x = 1 }"],
            architecturalContext: "Swift 6 actors only"
        )

        let prompt = PromptGenerator.generatePrompt(for: task)
        #expect(prompt.contains("# TASK: Test Task"))
        #expect(prompt.contains("Swift 6 actors only"))
        #expect(prompt.contains("struct Target"))
        #expect(prompt.count <= PromptGenerator.maxPromptCharacters)
    }

    @Test func testEvaluateQuotaPolicyDaytimeRespectsThreshold() {
        let scheduler = AIScheduler(daytimeStartHour: 8, daytimeEndHour: 22, daytimeMaxQuotaUse: 30.0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let midday = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 13, minute: 0))!

        let lowQuota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 20.0, windowMinutes: 300, resetsAt: midday.addingTimeInterval(3600))
        )
        let decisionOk = scheduler.evaluateQuotaPolicy(now: midday, quota: lowQuota, calendar: cal)
        #expect(decisionOk.allowed)
        #expect(decisionOk.mode == .daytimeUserReserve)

        let highQuota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 40.0, windowMinutes: 300, resetsAt: midday.addingTimeInterval(3600))
        )
        let decisionBlocked = scheduler.evaluateQuotaPolicy(now: midday, quota: highQuota, calendar: cal)
        #expect(!decisionBlocked.allowed)
        #expect(decisionBlocked.mode == .daytimeUserReserve)
    }

    @Test func testEvaluateQuotaPolicyNighttimeConservesMorningWake() {
        let scheduler = AIScheduler(daytimeStartHour: 8, daytimeEndHour: 22, daytimeMaxQuotaUse: 30.0, nighttimeMaxQuotaUse: 90.0)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // 04:00 AM
        let nightTime = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 4, minute: 0))!
        // Resets at 09:30 AM (after 08:00 AM user wake) with 50% usage
        let resetAfterWake = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9, minute: 30))!

        let dangerousQuota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 50.0, windowMinutes: 300, resetsAt: resetAfterWake)
        )
        let decisionDangerous = scheduler.evaluateQuotaPolicy(now: nightTime, quota: dangerousQuota, calendar: cal, userWakeHour: 8)
        #expect(!decisionDangerous.allowed)
        #expect(decisionDangerous.mode == .nighttimeAutonomous)
        #expect(decisionDangerous.reason.contains("not guarantee"))

        // Resets at 06:30 AM (before 08:00 AM user wake) -> safe to run!
        let resetBeforeWake = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 6, minute: 30))!
        let safeQuota = CodexQuota(
            planType: "plus",
            primary: QuotaWindow(usedPercent: 50.0, windowMinutes: 300, resetsAt: resetBeforeWake)
        )
        let decisionSafe = scheduler.evaluateQuotaPolicy(now: nightTime, quota: safeQuota, calendar: cal, userWakeHour: 8)
        #expect(decisionSafe.allowed)
        #expect(decisionSafe.mode == .nighttimeAutonomous)
    }

    @Test func testDualAIEngineRoutingRecommendation() {
        #expect(DualAIEngine.recommendProvider(for: "Fix Swift 6 concurrency warnings in actor") == .gemini)
        #expect(DualAIEngine.recommendProvider(for: "Deep architecture audit of SQLite storage") == .gemini)
        #expect(DualAIEngine.recommendProvider(for: "Build fluid SwiftUI Notch View") == .codex)
        #expect(DualAIEngine.recommendProvider(for: "General project feature task") == .codex)
    }

    @Test func testPromptGeneratorContextualTask() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let contextFile = tempDir.appendingPathComponent("newton.md")
        try? "Unified personal super-app combining Screenpipe, Vorssaint and Lumen.".write(to: contextFile, atomically: true, encoding: .utf8)

        let task = PromptGenerator.makeContextualTask(
            title: "Build Feature",
            objective: "Add new capability",
            repoRoot: tempDir
        )

        #expect(task.title == "Build Feature")
        #expect(task.architecturalContext.contains("Unified personal super-app"))
    }
}
