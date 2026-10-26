import Foundation

public enum TaxLineCategory: String, Sendable, CaseIterable, Codable {
    case softwareSaaS = "Line 18 (Office / SaaS Software)"
    case hardwareSupplies = "Line 22 (Supplies & Hardware)"
    case businessMeals = "Line 24b (Business Meals 50%)"
    case professionalServices = "Line 17 (Legal & Professional)"
    case advertising = "Line 8 (Advertising & Marketing)"
}

public struct TaxDeductionItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let vendor: String
    public let amount: Double
    public let date: Date
    public let category: TaxLineCategory

    public init(id: UUID = UUID(), vendor: String, amount: Double, date: Date, category: TaxLineCategory) {
        self.id = id
        self.vendor = vendor
        self.amount = amount
        self.date = date
        self.category = category
    }

    public var deductibleAmount: Double {
        switch category {
        case .businessMeals:
            return amount * 0.50
        default:
            return amount
        }
    }
}

public struct SubscriptionRenewalItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let serviceName: String
    public let amount: Double
    public let renewalDate: Date
    public let priorAmount: Double?

    public init(id: UUID = UUID(), serviceName: String, amount: Double, renewalDate: Date, priorAmount: Double? = nil) {
        self.id = id
        self.serviceName = serviceName
        self.amount = amount
        self.renewalDate = renewalDate
        self.priorAmount = priorAmount
    }

    public var isImminent: Bool {
        let diff = Calendar.current.dateComponents([.day], from: Date(), to: renewalDate).day ?? 999
        return diff >= 0 && diff <= 3
    }

    public var hasPriceHike: Bool {
        guard let prior = priorAmount else { return false }
        return amount > prior
    }

    public var hikeDifference: Double {
        guard let prior = priorAmount, hasPriceHike else { return 0 }
        return amount - prior
    }
}

public struct FinancialRunwaySummary: Sendable, Equatable {
    public let totalMonthlyBurn: Double
    public let projectedAnnualRunway: Double?
    public let totalTaxDeductions: Double
    public let estimatedTaxSavings: Double?
    public let imminentRenewals: [SubscriptionRenewalItem]

    public init(totalMonthlyBurn: Double, projectedAnnualRunway: Double?, totalTaxDeductions: Double, estimatedTaxSavings: Double?, imminentRenewals: [SubscriptionRenewalItem]) {
        self.totalMonthlyBurn = totalMonthlyBurn
        self.projectedAnnualRunway = projectedAnnualRunway
        self.totalTaxDeductions = totalTaxDeductions
        self.estimatedTaxSavings = estimatedTaxSavings
        self.imminentRenewals = imminentRenewals
    }
}

/// Lumen Financial Runway & IRS Schedule-C Tax Deduction Engine.
public enum FinancialRunwayEngine: Sendable {
    public static func computeSummary(
        subscriptions: [SubscriptionRenewalItem],
        deductions: [TaxDeductionItem],
        availableLiquidCash: Double? = nil,
        verifiedTaxRate: Double? = nil
    ) -> FinancialRunwaySummary {
        let monthlyBurn = subscriptions.reduce(0.0) { $0 + $1.amount }
        let totalDeductible = deductions.reduce(0.0) { $0 + $1.deductibleAmount }
        let estimatedSavings = verifiedTaxRate.flatMap { rate in rate.isFinite && (0...1).contains(rate) ? totalDeductible * rate : nil }

        let imminent = subscriptions.filter { $0.isImminent }
        let runwayMonths = availableLiquidCash.flatMap { cash in cash.isFinite && cash >= 0 && monthlyBurn > 0 ? cash / monthlyBurn : nil }

        return FinancialRunwaySummary(
            totalMonthlyBurn: monthlyBurn,
            projectedAnnualRunway: runwayMonths,
            totalTaxDeductions: totalDeductible,
            estimatedTaxSavings: estimatedSavings,
            imminentRenewals: imminent
        )
    }

    /// Auto-categorizes an expense description into an IRS Schedule-C line.
    public static func categorizeExpense(vendor: String) -> TaxLineCategory {
        let lower = vendor.lowercased()
        if lower.contains("aws") || lower.contains("openai") || lower.contains("anthropic") || lower.contains("github") || lower.contains("google cloud") || lower.contains("digitalocean") || lower.contains("cursor") {
            return .softwareSaaS
        } else if lower.contains("apple") || lower.contains("best buy") || lower.contains("b&h") || lower.contains("hardware") || lower.contains("keychron") {
            return .hardwareSupplies
        } else if lower.contains("restaurant") || lower.contains("coffee") || lower.contains("starbucks") || lower.contains("uber eats") || lower.contains("doordash") {
            return .businessMeals
        } else if lower.contains("law") || lower.contains("legal") || lower.contains("accounting") || lower.contains("cpa") {
            return .professionalServices
        } else if lower.contains("meta ads") || lower.contains("google ads") || lower.contains("x ads") || lower.contains("adwords") {
            return .advertising
        }
        return .softwareSaaS
    }
}
