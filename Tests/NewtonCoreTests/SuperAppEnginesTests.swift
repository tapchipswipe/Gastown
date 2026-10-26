import Testing
import Foundation
@testable import NewtonCore

struct SuperAppEnginesTests {
    // MARK: - CommandBarEngine Tests

    @Test func testMathEvaluationComputesCorrectly() {
        #expect(CommandBarEngine.evaluateMath("2 + 2 * 3") == "= 8")
        #expect(CommandBarEngine.evaluateMath("100 / 4 - 5") == "= 20")
        #expect(CommandBarEngine.evaluateMath("10 * 10") == "= 100")
        #expect(CommandBarEngine.evaluateMath("plain text words") == nil)
        #expect(CommandBarEngine.evaluateMath("123") == nil) // single number without operator is not an equation
        #expect(CommandBarEngine.evaluateMath("") == nil)
    }

    @Test func testUnitConversions() {
        let kmResult = CommandBarEngine.convertUnits("100 km to mi")
        #expect(kmResult != nil)
        #expect(kmResult?.contains("mi") == true)

        let tempResult = CommandBarEngine.convertUnits("0 c to f")
        #expect(tempResult == "32.0 °F")

        let storageResult = CommandBarEngine.convertUnits("2048 mb to gb")
        #expect(storageResult == "2.00 GB")

        let weightResult = CommandBarEngine.convertUnits("10 kg to lbs")
        #expect(weightResult != nil)
        #expect(weightResult?.contains("lbs") == true)

        #expect(CommandBarEngine.convertUnits("random query") == nil)
        #expect(CommandBarEngine.convertUnits("10 invalid to unknown") == nil)
    }

    @Test func testActionMatchingFiltersCorrectly() {
        let allActions = CommandBarEngine.matchActions(query: "")
        #expect(allActions.count >= 8)

        let standupActions = CommandBarEngine.matchActions(query: "standup")
        #expect(standupActions.count == 1)
        #expect(standupActions.first?.id == "standup")

        let awakeActions = CommandBarEngine.matchActions(query: "awake")
        #expect(awakeActions.count == 1)
        #expect(awakeActions.first?.id == "keepAwake")

        let emptySearch = CommandBarEngine.matchActions(query: "nonexistentXYZ123")
        #expect(emptySearch.isEmpty)
    }

    // MARK: - PipeAutomationEngine Tests

    @Test func testStandupSynthesizerBuildsValidReport() {
        let events = [
            HistoryEvent(source: "Activity", title: "Xcode"),
            HistoryEvent(source: "Activity", title: "Cursor"),
            HistoryEvent(source: "CLI", title: "git commit -m 'feat: dynamic notch'"),
            HistoryEvent(source: "ScreenCapture", title: "Build error encountered in test runner")
        ]
        let projects = [
            TrackedProject(name: "newton", path: "/Users/test/newton", activeBranch: "main", condition: .clean, lastCommitMessage: "feat: liquid glass", lastCommitDate: Date())
        ]

        let report = PipeAutomationEngine.synthesizeStandup(events: events, projects: projects)
        #expect(!report.yesterday.isEmpty)
        #expect(!report.today.isEmpty)
        #expect(!report.blockers.isEmpty)
        #expect(report.fullMarkdown.contains("# 📋 Daily Engineering Standup"))
        #expect(report.fullMarkdown.contains("newton"))
    }

    @Test func testSOPGeneratorBuildsStructuredProcedure() {
        let actions = [
            HistoryEvent(source: "Activity", title: "Safari", detail: "Open https://github.com"),
            HistoryEvent(source: "Activity", title: "Terminal", detail: "Run ./build.sh")
        ]

        let sop = PipeAutomationEngine.generateSOP(title: "Release Deployment", recordedActions: actions)
        #expect(sop.title == "Release Deployment")
        #expect(sop.steps.count == 2)
        #expect(sop.steps[0].id == 1)
        #expect(sop.markdownSOP.contains("Release Deployment"))
        #expect(sop.markdownSOP.contains("Safari"))
    }

    // MARK: - FinancialRunwayEngine Tests

    @Test func testExpenseAutoCategorization() {
        #expect(FinancialRunwayEngine.categorizeExpense(vendor: "OpenAI API") == .softwareSaaS)
        #expect(FinancialRunwayEngine.categorizeExpense(vendor: "AWS Cloud") == .softwareSaaS)
        #expect(FinancialRunwayEngine.categorizeExpense(vendor: "Apple Store MacBook") == .hardwareSupplies)
        #expect(FinancialRunwayEngine.categorizeExpense(vendor: "Starbucks Coffee Meeting") == .businessMeals)
        #expect(FinancialRunwayEngine.categorizeExpense(vendor: "Cooley Law Firm") == .professionalServices)
        #expect(FinancialRunwayEngine.categorizeExpense(vendor: "Google Ads Campaign") == .advertising)
    }

    @Test func testDeduction50PercentRuleForBusinessMeals() {
        let meal = TaxDeductionItem(vendor: "Lunch", amount: 100.0, date: Date(), category: .businessMeals)
        #expect(meal.deductibleAmount == 50.0)

        let software = TaxDeductionItem(vendor: "Cursor", amount: 20.0, date: Date(), category: .softwareSaaS)
        #expect(software.deductibleAmount == 20.0)
    }

    @Test func testSubscriptionImminenceAndPriceHikeDetection() {
        let imminentSub = SubscriptionRenewalItem(
            serviceName: "Claude",
            amount: 40.0,
            renewalDate: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            priorAmount: 30.0
        )
        #expect(imminentSub.isImminent == true)
        #expect(imminentSub.hasPriceHike == true)
        #expect(imminentSub.hikeDifference == 10.0)

        let normalSub = SubscriptionRenewalItem(
            serviceName: "GitHub",
            amount: 10.0,
            renewalDate: Calendar.current.date(byAdding: .day, value: 20, to: Date())!,
            priorAmount: 10.0
        )
        #expect(normalSub.isImminent == false)
        #expect(normalSub.hasPriceHike == false)
    }

    @Test func testFinancialRunwaySummaryCalculation() {
        let subs = [
            SubscriptionRenewalItem(serviceName: "SaaS 1", amount: 100.0, renewalDate: Date()),
            SubscriptionRenewalItem(serviceName: "SaaS 2", amount: 200.0, renewalDate: Date())
        ]
        let deductions = [
            TaxDeductionItem(vendor: "SaaS 1", amount: 100.0, date: Date(), category: .softwareSaaS),
            TaxDeductionItem(vendor: "Meals", amount: 200.0, date: Date(), category: .businessMeals)
        ]

        let summary = FinancialRunwayEngine.computeSummary(
            subscriptions: subs,
            deductions: deductions,
            availableLiquidCash: 30000.0, verifiedTaxRate: 0.28
        )

        #expect(summary.totalMonthlyBurn == 300.0)
        #expect(summary.totalTaxDeductions == 200.0) // 100 + (200 * 0.5)
        #expect(abs((summary.estimatedTaxSavings ?? -1) - 56.0) < 0.001) // 200 * 0.28
        #expect(summary.projectedAnnualRunway == 100.0) // 30000 / 300
    }
}
