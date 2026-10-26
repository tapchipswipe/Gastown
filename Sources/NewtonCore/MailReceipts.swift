import Foundation
import CryptoKit

public enum ReceiptKind: String, Codable, Sendable { case payment, refund, invoice, failedPayment, transfer, shipping, ambiguous }
public struct MailMessage: Codable, Sendable, Equatable {
    public let sourceID: String
    public let nativeID: Int
    public let mailboxID: String
    public let sender: String
    public let subject: String
    public let receivedAt: Date
    public let body: String
    public init(sourceID: String, nativeID: Int = 0, mailboxID: String = "fixture", sender: String, subject: String, receivedAt: Date, body: String) {
        self.sourceID = sourceID; self.nativeID = nativeID; self.mailboxID = mailboxID; self.sender = sender; self.subject = subject; self.receivedAt = receivedAt; self.body = body
    }
}
public struct ReceiptRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let sourceMessageID: String
    public let merchant: String
    public let service: String?
    public let amount: Decimal?
    public let currency: String?
    public let transactionDate: Date?
    public let receivedAt: Date
    public let kind: ReceiptKind
    public let evidence: String
    public let confidence: Double
    public let billingMonths: Int?
    public var isConfirmed: Bool { (kind == .payment || kind == .refund) && amount != nil && currency != nil && transactionDate != nil && confidence >= 0.9 }
}
public enum ReceiptParser {
    public static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]) else { return [] }
        let source = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: source.length)).map { match in
            (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : source.substring(with: match.range(at: $0)) }
        }
    }
    public static func parse(_ message: MailMessage) -> ReceiptRecord? {
        let text = String((message.subject + "\n" + message.body).prefix(30_000)), lower = text.lowercased()
        let kind: ReceiptKind
        if ["payment failed", "payment declined", "could not charge", "past due"].contains(where: lower.contains) { kind = .failedPayment }
        else if ["shipping confirmation", "shipment", "out for delivery", "tracking number"].contains(where: lower.contains) { kind = .shipping }
        else if ["bank transfer", "funds transfer", "money transfer"].contains(where: lower.contains) { kind = .transfer }
        else if ["refund issued", "refunded", "refund processed"].contains(where: lower.contains) { kind = .refund }
        else if ["payment successful", "payment received", "payment processed", "amount paid", "you paid", "you were charged", "paid receipt", "thank you for your payment", "successfully charged", "payment confirmation", "total paid", "amount charged", "date paid"].contains(where: lower.contains) { kind = .payment }
        else if lower.contains("invoice") { kind = .invoice }
        else if lower.contains("receipt") || lower.contains("subscription") { kind = .ambiguous }
        else { return nil }
        let money = captures(#"(?:^|\n)\s*(?:total paid|amount paid|amount charged|total amount|amount refunded|you paid|you were charged|total|refunded)\s*[:\-]?\s*(USD|EUR|GBP|CAD|AUD|JPY|CHF|US\$|€|£|\$)?\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]{2})?)(?![0-9.,])\s*(USD|EUR|GBP|CAD|AUD|JPY|CHF)?\b"#, text)
        var amounts: [(Decimal, String?)] = []
        for match in money {
            guard let amount = Decimal(string: match[2].replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")), amount > 0, amount < 100_000_000 else { continue }
            let label = (match[3].isEmpty ? match[1] : match[3]).uppercased()
            let currency: String? = ["USD","EUR","GBP","CAD","AUD","JPY","CHF"].contains(label) ? label : (["US$":"USD","€":"EUR","£":"GBP"][label])
            amounts.append((amount, currency))
        }
        let unique = Set(amounts.map { "\($0.0):\($0.1 ?? "?")" })
        let amount = unique.count == 1 ? amounts.first?.0 : nil
        let currency = unique.count == 1 ? amounts.first?.1 : nil
        let dateMatch = captures(#"^\s*(?:transaction date|payment date|date paid|paid on|refund date|date)\s*:?\s*(\d{4}-\d{2}-\d{2}|[A-Za-z]{3,9}\s+\d{1,2},?\s+\d{4}|\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4})\b"#,text).first
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.isLenient = false
        var date: Date?
        if let raw = dateMatch?[1] {
            for format in ["yyyy-MM-dd","MMMM d, yyyy","MMM d, yyyy","MMMM d yyyy","MMM d yyyy","d MMMM yyyy","d MMM yyyy"] {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: raw) { date = parsed; break }
            }
        }
        let service = captures(#"^(?:service|subscription|product)\s*:\s*([^\r\n]{1,120})"#, text).first?[1].trimmingCharacters(in: .whitespaces)
        let reference = captures(#"(?:transaction|payment|refund)\s*(?:id|reference|number|#)\s*[:#]?\s*([A-Z0-9][A-Z0-9_\-]{5,100})"#, text).first?[1]
        let merchant = message.sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let identity = reference.map { "\(merchant)|\(kind.rawValue)|\($0)|\(currency ?? "?")|\(amount?.description ?? "?")" } ?? message.sourceID
        let confidence = amount != nil && currency != nil && date != nil && date! <= message.receivedAt.addingTimeInterval(86400) && (kind == .payment || kind == .refund) ? 0.95 : 0.5
        let billing = lower.contains("billed monthly") || lower.contains("monthly subscription") ? 1 : (lower.contains("billed annually") || lower.contains("annual subscription") ? 12 : nil)
        return ReceiptRecord(id: digest(identity), sourceMessageID: message.sourceID, merchant: merchant, service: service, amount: amount, currency: currency, transactionDate: date, receivedAt: message.receivedAt, kind: kind, evidence: String(text.prefix(3000)), confidence: confidence, billingMonths: billing)
    }
}
public struct ReceiptSpending: Sendable {
    public let payments: [String: Decimal]
    public let refunds: [String: Decimal]
    public let excluded: Int
    public init(_ receipts: [ReceiptRecord]) {
        var payments: [String: Decimal] = [:], refunds: [String: Decimal] = [:], excluded = 0
        for item in receipts {
            guard item.isConfirmed, let amount = item.amount, let currency = item.currency else { excluded += 1; continue }
            if item.kind == .payment { payments[currency, default: 0] += amount } else { refunds[currency, default: 0] += amount }
        }
        self.payments = payments; self.refunds = refunds; self.excluded = excluded
    }
}
public struct PredictedRenewal: Codable, Sendable, Identifiable {
    public let id: String
    public let service: String
    public let currency: String
    public let amount: Decimal
    public let predictedDate: Date
    public let priorAmount: Decimal?
    public let sourceIDs: [String]
    public var hasPriceIncrease: Bool { priorAmount.map { amount > $0 } ?? false }
}
public enum ReceiptRecurrence {
    public static func predictions(_ receipts: [ReceiptRecord], now: Date = Date(), calendar: Calendar = .current) -> [PredictedRenewal] {
        let confirmed = receipts.filter { $0.isConfirmed && $0.kind == .payment }
        let grouped = Dictionary(grouping: confirmed) { $0.merchant + "|" + ($0.service ?? "") + "|" + ($0.currency ?? "") }
        var receiptCalendar = Calendar(identifier: .gregorian); receiptCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = receiptCalendar.startOfDay(for: now)
        return grouped.compactMap { key, records in
            let sorted = records.sorted { $0.transactionDate! < $1.transactionDate! }
            guard let latest = sorted.last, let date = latest.transactionDate, let currency = latest.currency, let amount = latest.amount else { return nil }
            let service = latest.service ?? (latest.merchant + " · service unspecified")
            let previous = sorted.dropLast().last
            var months = latest.billingMonths
            if months == nil, let previous, previous.amount == latest.amount, let priorDate = previous.transactionDate {
                let days = date.timeIntervalSince(priorDate) / 86400
                if (25...35).contains(days) { months = 1 }; if (330...400).contains(days) { months = 12 }
            }
            guard let months, let next = receiptCalendar.date(byAdding: .month, value: months, to: date), next >= today,
                  next <= today.addingTimeInterval(30 * 86400) else { return nil }
            return PredictedRenewal(id: key, service: service, currency: currency, amount: amount, predictedDate: next, priorAmount: latest.service != nil ? previous?.amount : nil, sourceIDs: [latest.sourceMessageID] + (previous.map { [$0.sourceMessageID] } ?? []))
        }.sorted { $0.predictedDate < $1.predictedDate }
    }
}
