import Foundation
import Testing
import CSQLite
@testable import NewtonCore

struct AutomaticIntelligenceTests {
    func message(_ id: String = "one",kind: String = "Payment successful",currency: String = "USD",amount: String = "12.34",date: String = "2026-10-01",reference: String = "TX123456") -> MailMessage {
        MailMessage(sourceID: id,sender: "Example <billing@example.com>",subject: kind,receivedAt: Date(),body: "Amount paid: \(currency) \(amount)\nPayment date: \(date)\nTransaction ID: \(reference)\nSubscription: Developer plan\nBilled monthly")
    }
    @Test func decimalReceiptsSeparateCurrenciesAndExcludeAmbiguity() throws {
        let payment = try #require(ReceiptParser.parse(message()))
        #expect(payment.isConfirmed)
        #expect(payment.amount == Decimal(string: "12.34"))
        let refund = try #require(ReceiptParser.parse(message("refund",kind: "Refund issued",reference: "RF123456")))
        let euro = try #require(ReceiptParser.parse(message("euro",currency: "EUR")))
        let ambiguous = try #require(ReceiptParser.parse(message("dollar",currency: "$")))
        let failed = try #require(ReceiptParser.parse(message("failed",kind: "Payment failed")))
        let invoice = try #require(ReceiptParser.parse(MailMessage(sourceID: "invoice",sender: "Vendor",subject: "Invoice",receivedAt: Date(),body: "Total: USD 99.00\nDate: 2026-10-01")))
        let summary = ReceiptSpending([payment,refund,euro,ambiguous,failed,invoice])
        #expect(summary.payments["USD"] == Decimal(string: "12.34"))
        #expect(summary.payments["EUR"] == Decimal(string: "12.34"))
        #expect(summary.refunds["USD"] == Decimal(string: "12.34"))
        #expect(summary.excluded == 3)
        #expect(ReceiptParser.parse(MailMessage(sourceID: "plain",sender: "a",subject: "Hello",receivedAt: Date(),body: "No transaction")) == nil)
        #expect(ReceiptParser.parse(message("bad",amount: "nonsense"))?.isConfirmed == false)
    }
    @Test func sourceAndEvidenceDeduplicationAndCheckpointShareCommit() async throws {
        let store = try IntelligenceStore(path: ":memory:")
        let one = try #require(ReceiptParser.parse(message("source-one"))), duplicate = try #require(ReceiptParser.parse(message("source-two")))
        #expect(one.id == duplicate.id)
        let checkpoint = MailCheckpoint(mailboxID: "inbox",cutoff: .distantPast,afterNativeID: 12)
        try await store.commitMail([one,duplicate],processedIDs: ["source-one","source-two"],checkpoint: checkpoint)
        #expect(try await store.list(ReceiptRecord.self,namespace: "receipts").count == 1)
        #expect(try await store.mailProcessed("source-two"))
        #expect(try await store.load(MailCheckpoint.self,namespace: "mail-checkpoints",id: "inbox")?.afterNativeID == 12)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.commitMail([],processedIDs: ["uncommitted"],checkpoint: MailCheckpoint(mailboxID: "inbox",cutoff: .distantPast,afterNativeID: 999))
        }
        _ = await task.result
        #expect(try await store.mailProcessed("uncommitted") == false)
        #expect(try await store.load(MailCheckpoint.self,namespace: "mail-checkpoints",id: "inbox")?.afterNativeID == 12)
    }
    @Test func predictedRenewalsRequireComparableServiceCurrencyEvidence() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-10-02T00:00:00Z")!
        let prior = try #require(ReceiptParser.parse(message("prior",amount: "10.00",date: "2026-09-01",reference: "TX000001")))
        let current = try #require(ReceiptParser.parse(message("current",amount: "12.34",date: "2026-10-01",reference: "TX000002")))
        let predictions = ReceiptRecurrence.predictions([prior,current],now: now,calendar: calendar)
        #expect(predictions.count == 1 && predictions[0].hasPriceIncrease)
        #expect(predictions[0].sourceIDs.count == 2)
        #expect(ReceiptRecurrence.predictions([prior],now: now,calendar: calendar).isEmpty)
    }
    @Test func dailySchedulerCatchesUpAndPreservesDSTAndChangedEvidence() async throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = ISO8601DateFormatter().date(from: "2026-11-02T14:00:00Z")!
        let day = try #require(DailyReportService.dueRange(now: now,calendar: calendar))
        #expect(day.duration == 25 * 3600)
        let before = calendar.date(bySettingHour: 8,minute: 14,second: 0,of: now)!
        #expect(DailyReportService.dueRange(now: before,calendar: calendar) == nil)
        let history = try EventStore(path: ":memory:"), store = try IntelligenceStore(path: ":memory:")
        try await history.append((0..<1001).map { HistoryEvent(id: "obs-\($0)",timestamp: day.start,source: "fixture",title: "TODO: \($0)") })
        let service = DailyReportService(history: history,store: store)
        let first = try #require(try await service.generateIfDue(now: now,calendar: calendar))
        #expect(first.observationCount == 1001 && first.databaseRangeComplete)
        let unchanged = try #require(try await service.generateIfDue(now: now.addingTimeInterval(10),calendar: calendar))
        #expect(first.generatedAt == unchanged.generatedAt)
        try await history.append([HistoryEvent(id: "late",timestamp: day.start,source: "fixture",title: "Late evidence")])
        let updated = try #require(try await service.generateIfDue(now: now.addingTimeInterval(20),calendar: calendar))
        #expect(updated.observationCount == 1002 && updated.inputDigest != first.inputDigest)
    }
    @Test func newerIntelligenceSchemaIsRejectedWithoutReset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("future.sqlite").path
        var db: OpaquePointer?; sqlite3_open(path,&db); sqlite3_exec(db,"PRAGMA user_version=99",nil,nil,nil); sqlite3_close(db)
        #expect(throws: StoreError.self) { try IntelligenceStore(path: path) }
    }
}

actor FixtureMailReader: MailReading {
    let messages: [MailMessage]
    var fail = false
    init(_ messages: [MailMessage]) { self.messages = messages }
    func setFailure(_ value: Bool) { fail = value }
    func inventory() -> MailInventory { MailInventory(mailboxes: [MailboxDescriptor(id: "fixture",accountID: "account",path: ["Inbox"])],unavailable: []) }
    func batch(mailbox: MailboxDescriptor,afterNativeID: Int,cutoff: Date,limit: Int) throws -> MailMessageBatch {
        if fail { throw StoreError(message: "Retryable fixture error") }
        return MailMessageBatch(messages: messages,nextNativeID: 1,complete: true)
    }
}
struct MailCollectorRetryTests {
    @Test func retriesAndRepeatedReadOnlyIntakeAreDuplicateSafe() async throws {
        let source = AutomaticIntelligenceTests().message(), reader = FixtureMailReader([source]), store = try IntelligenceStore(path: ":memory:")
        let collector = MailReceiptCollector(store: store,reader: reader)
        await reader.setFailure(true)
        #expect(try await collector.collect().complete == false)
        #expect(try await store.load(MailCheckpoint.self,namespace: "mail-checkpoints",id: "fixture") == nil)
        await reader.setFailure(false)
        #expect(try await collector.collect(force: true).committedMessages == 1)
        #expect(try await collector.collect(force: true).committedMessages == 0)
        #expect(try await store.list(ReceiptRecord.self,namespace: "receipts").count == 1)
        #expect(AppleMailReader.script.contains("readStatus") == false)
        #expect(AppleMailReader.script.contains(".send(") == false)
        #expect(AppleMailReader.script.contains(".quit(") == false)
    }
}

struct MailWireFormatTests {
    @Test func nativeJXAFractionalDatesAndLocalizedJunkAreHandled() throws {
        let json = #"{"messages":[{"sourceID":"rfc-message","nativeID":1,"sender":"Vendor","subject":"Receipt","received":"2026-10-25T17:00:00.000Z","body":"Body"}],"next":1,"complete":true,"unavailable":[]}"#
        let batch = try AppleMailReader.decodeBatch(Data(json.utf8),mailbox: MailboxDescriptor(id: "fixture",accountID: "account",path: ["Inbox"]))
        #expect(batch.messages.count == 1)
        #expect(batch.messages[0].receivedAt == ISO8601DateFormatter().date(from: "2026-10-25T17:00:00Z"))
        #expect(AppleMailReader.script.contains("[\\s\\/_-]") == true)
    }
}

struct LiveMailAcceptance {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NEWTON_LIVE_MAIL_ACCEPTANCE"] == "1"))
    func readOnlyMailTwiceRetainsSourceEvidenceWithoutDuplicates() async throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NEWTON_ACCEPTANCE_DIRECTORY"] ?? "/tmp/newton-live-mail-acceptance")
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        let reader = AppleMailReader(), inventory = try await reader.inventory()
        let choices = inventory.mailboxes.filter { ["inbox","archive"].contains($0.path.last?.lowercased() ?? "") }
        try #require(choices.isEmpty == false)
        let store = try IntelligenceStore(path: directory.appendingPathComponent("mail-acceptance.sqlite").path)
        let cutoff = Calendar.current.date(byAdding: .month,value: -12,to: Date())!
        var observed = 0, receipts = 0, repeated = 0
        for box in choices.prefix(4) {
            let first = try await reader.receiptSample(mailbox: box,cutoff: cutoff,limit: 20)
            let second = try await reader.receiptSample(mailbox: box,cutoff: cutoff,limit: 20)
            let parsed = first.messages.compactMap(ReceiptParser.parse), again = second.messages.compactMap(ReceiptParser.parse)
            let checkpoint = MailCheckpoint(mailboxID: box.id,cutoff: cutoff,afterNativeID: first.nextNativeID)
            try await store.commitMail(parsed,processedIDs: first.messages.map(\.sourceID),checkpoint: checkpoint)
            let before = try await store.list(ReceiptRecord.self,namespace: "receipts").count
            try await store.commitMail(again,processedIDs: second.messages.map(\.sourceID),checkpoint: checkpoint)
            let after = try await store.list(ReceiptRecord.self,namespace: "receipts").count
            let newIDs = Set(again.map(\.id)).subtracting(Set(parsed.map(\.id)))
            #expect(after - before <= newIDs.count)
            observed += first.messages.count; receipts += parsed.count
            repeated += Set(first.messages.map(\.sourceID)).intersection(Set(second.messages.map(\.sourceID))).count
        }
        let stored = try await store.list(ReceiptRecord.self,namespace: "receipts")
        #expect(stored.allSatisfy { !$0.sourceMessageID.isEmpty && !$0.evidence.isEmpty })
        #expect(observed > 0 && repeated > 0 && stored.isEmpty == false)
        let receipt: [String: Any] = ["observedMessages":observed,"receiptCandidates":receipts,"repeatedSourceIdentities":repeated,"storedUniqueCandidates":stored.count,"unavailableInventorySources":inventory.unavailable.count,"messagesModified":false,"scope":"Bounded live sample, not full backfill acceptance"]
        try JSONSerialization.data(withJSONObject: receipt,options: [.prettyPrinted,.sortedKeys]).write(to: directory.appendingPathComponent("mail-summary.json"),options: .atomic)
    }
}

struct ReceiptParsingBoundaryTests {
    @Test func malformedDecimalsAndDueDatesCannotBecomeConfirmedPayments() {
        let received = ISO8601DateFormatter().date(from: "2026-10-25T00:00:00Z")!
        for body in ["Total: EUR 12,34\nDate: 2026-10-01","Total: USD 12.345\nDate: 2026-10-01","Total: USD 12.34\nDue date: 2026-11-01","Total: USD 12.34\nDate: 2099-01-01"] {
            let receipt = ReceiptParser.parse(MailMessage(sourceID: "boundary",sender: "Vendor",subject: "Payment successful",receivedAt: received,body: body))
            #expect(receipt?.isConfirmed == false)
        }
        let valid = ReceiptParser.parse(MailMessage(sourceID: "month-name",sender: "Vendor",subject: "Payment successful",receivedAt: received,body: "Total paid: USD 1,234.56\nPayment date: October 1, 2026"))
        #expect(valid?.isConfirmed == true)
        #expect(valid?.amount == Decimal(string: "1234.56"))
    }
    @Test func unspecifiedServiceDoesNotProducePriceHikeClaims() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-02T00:00:00Z")!
        let receipt = try #require(ReceiptParser.parse(MailMessage(sourceID: "unknown-service",sender: "Vendor",subject: "Payment successful",receivedAt: now,body: "Total: USD 12.34\nDate: 2026-10-01\nBilled monthly")))
        let predictions = ReceiptRecurrence.predictions([receipt],now: now)
        #expect(predictions.first?.service.contains("unspecified") == true)
        #expect(predictions.first?.hasPriceIncrease == false)
    }
    @Test func transcriptRotationPreservesFinalSegmentsAndChannelIdentity() {
        var accumulator = TranscriptAccumulator(channel: "system")
        accumulator.update("First sentence",isFinal: true)
        let firstID = accumulator.segments.first?.id
        accumulator.beginSegment(); accumulator.update("Second",isFinal: false); accumulator.update("Second sentence",isFinal: true)
        #expect(accumulator.segments.count == 2)
        #expect(accumulator.segments[0].id == firstID)
        #expect(accumulator.segments[1].id != firstID)
        #expect(accumulator.segments.allSatisfy { $0.sourceChannel == "system" && $0.isFinal })
    }
}

actor FairMailboxReader: MailReading {
    func inventory() -> MailInventory { MailInventory(mailboxes: ["A","B"].map { MailboxDescriptor(id: $0,accountID: $0,path: ["Inbox"]) },unavailable: []) }
    func recentBatch(mailbox: MailboxDescriptor,cutoff: Date,limit: Int) async throws -> MailMessageBatch { MailMessageBatch(messages: [],nextNativeID: 1,complete: false) }
    func batch(mailbox: MailboxDescriptor,afterNativeID: Int,cutoff: Date,limit: Int) -> MailMessageBatch { MailMessageBatch(messages: [],nextNativeID: afterNativeID+1,complete: mailbox.id == "B") }
}
struct MailFairnessTests {
    @Test func largeBackfillDoesNotStarveOtherMailboxOrRecentSeed() async throws {
        let store = try IntelligenceStore(path: ":memory:"), collector = MailReceiptCollector(store: store,reader: FairMailboxReader())
        let now = Date()
        for step in 0..<4 { _ = try await collector.collect(now: now.addingTimeInterval(Double(step)),maximumBatches: 1) }
        #expect(try await store.load(MailCheckpoint.self,namespace: "mail-checkpoints",id: "A")?.recentSeeded == true)
        #expect(try await store.load(MailCheckpoint.self,namespace: "mail-checkpoints",id: "B")?.completedAt != nil)
    }
    @Test func acceptanceRequiresMatchingBinaryAndRealDurationReceipt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("soak.json"), hash = String(repeating: "a",count: 64)
        let complete = RolloutAcceptance(nativeLaunch: true,menuAndShortcuts: true,selectedWindow: true,keyboardInterception: true,meetingTranscription: true,mailReadTwice: true,disposableCodexJob: true,realSleepWakeCycles: 2,binarySHA256: hash,soakReceiptPath: path.path)
        #expect(complete.denial(currentBinarySHA256: hash) != nil)
        let short: [String:Any] = ["complete":true,"requestedSeconds":10,"elapsedSeconds":10,"binarySHA256":hash,"errors":[]]
        try JSONSerialization.data(withJSONObject: short).write(to: path)
        #expect(complete.denial(currentBinarySHA256: hash) != nil)
        let full: [String:Any] = ["complete":true,"requestedSeconds":86400,"elapsedSeconds":86401,"binarySHA256":hash,"errors":[]]
        try JSONSerialization.data(withJSONObject: full).write(to: path)
        #expect(complete.denial(currentBinarySHA256: hash) == nil)
        #expect(complete.denial(currentBinarySHA256: String(repeating: "b",count: 64)) != nil)
        var missing = complete; missing.disposableCodexJob = false
        #expect(missing.denial(currentBinarySHA256: hash)?.contains("disposable") == true)
    }
}
