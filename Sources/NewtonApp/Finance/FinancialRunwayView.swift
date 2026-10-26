import SwiftUI
import NewtonCore
import NewtonWorkspace

public struct FinancialRunwayView: View {
    @Bindable var model: WorkspaceModel
    public init(model: WorkspaceModel) { self.model = model }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 16) {
                Text("Receipt-observed spending").font(.largeTitle.bold())
                Text("Apple Mail coverage only. Payments and refunds stay separate by currency. Ambiguous candidates, invoices, failed payments, transfers and shipping notices are excluded from confirmed totals.")
                Toggle("Read-only automatic Mail intake",isOn: Binding(get: { model.selectedFeatures.contains(.mailFinance) },set: { model.toggle(.mailFinance,enabled: $0) }))
                Text(model.serviceStates[.mailFinance]?.reason ?? "Mail intake off").font(.caption).foregroundStyle(.secondary)
                let totals = ReceiptSpending(model.automation.receipts)
                ForEach(totals.payments.keys.sorted(),id: \.self) { currency in
                    Text("\(currency) payments: \(totals.payments[currency]!.description) · refunds: \(totals.refunds[currency,default: 0].description)").font(.headline)
                }
                Text("\(totals.excluded) excluded candidates · Cash runway unavailable without a reliable balance source. Expense categories are potential classifications, not verified deductions.").font(.caption)
                Text("Predicted renewals · next 30 days").font(.headline)
                ForEach(model.automation.renewals) { item in
                    VStack(alignment: .leading) {
                        Text("\(item.service): \(item.currency) \(item.amount.description) · predicted \(String(item.predictedDate.ISO8601Format().prefix(10)))")
                        if item.hasPriceIncrease { Text("Comparable receipt price increase observed").foregroundStyle(.orange) }
                        Text("Sources: " + item.sourceIDs.joined(separator: ", ")).font(.caption).textSelection(.enabled)
                    }
                }
                Text("Receipt evidence").font(.headline)
                ForEach(model.automation.receipts.prefix(200)) { receipt in
                    DisclosureGroup("\(receipt.merchant) · \(receipt.kind.rawValue) · \(receipt.currency ?? "currency unknown") \(receipt.amount?.description ?? "amount unknown")") {
                        Text("Source message: " + receipt.sourceMessageID).font(.caption).textSelection(.enabled)
                        Text("Rule confidence: \(receipt.confidence.formatted()) · \(receipt.isConfirmed ? "confirmed receipt evidence" : "excluded from confirmed totals")").font(.caption)
                        Text(receipt.evidence).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }.padding(28)
        }
    }
}
