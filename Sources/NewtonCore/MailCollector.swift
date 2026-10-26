import Foundation

public struct MailboxDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let accountID: String
    public let path: [String]
    public init(id: String, accountID: String, path: [String]) { self.id = id; self.accountID = accountID; self.path = path }
}
public struct MailInventory: Codable, Sendable {
    public let mailboxes: [MailboxDescriptor]
    public let unavailable: [String]
}
public struct MailCheckpoint: Codable, Sendable, Equatable {
    public let mailboxID: String
    public var inProgress = true
    public var recentSeeded = false
    public var afterNativeID: Int
    public var processed: Int
    public var completedAt: Date?
    public var cutoff: Date
    public var checkedAt: Date
    public init(mailboxID: String, cutoff: Date, afterNativeID: Int = 0, processed: Int = 0, completedAt: Date? = nil, checkedAt: Date = Date()) {
        self.mailboxID = mailboxID; self.cutoff = cutoff; self.afterNativeID = afterNativeID; self.processed = processed; self.completedAt = completedAt; self.checkedAt = checkedAt; self.inProgress = completedAt == nil
    }
}
extension MailCheckpoint {
    private enum CodingKeys: String,CodingKey { case mailboxID,afterNativeID,processed,completedAt,cutoff,checkedAt,recentSeeded,inProgress }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mailboxID = try values.decode(String.self,forKey: .mailboxID)
        afterNativeID = try values.decode(Int.self,forKey: .afterNativeID); processed = try values.decode(Int.self,forKey: .processed)
        completedAt = try values.decodeIfPresent(Date.self,forKey: .completedAt)
        cutoff = try values.decode(Date.self,forKey: .cutoff); checkedAt = try values.decode(Date.self,forKey: .checkedAt)
        recentSeeded = try values.decodeIfPresent(Bool.self,forKey: .recentSeeded) ?? false
        inProgress = try values.decodeIfPresent(Bool.self,forKey: .inProgress) ?? (completedAt == nil)
    }
}
public struct MailMessageBatch: Sendable {
    public let messages: [MailMessage]
    public let nextNativeID: Int
    public let complete: Bool
    public let unavailable: [String]
    public init(messages: [MailMessage], nextNativeID: Int, complete: Bool, unavailable: [String] = []) { self.messages = messages; self.nextNativeID = nextNativeID; self.complete = complete; self.unavailable = unavailable }
}
public protocol MailReading: Sendable {
    func inventory() async throws -> MailInventory
    func recentBatch(mailbox: MailboxDescriptor,cutoff: Date,limit: Int) async throws -> MailMessageBatch
    func batch(mailbox: MailboxDescriptor, afterNativeID: Int, cutoff: Date, limit: Int) async throws -> MailMessageBatch
}

public extension MailReading {
    func recentBatch(mailbox: MailboxDescriptor,cutoff: Date,limit: Int) async throws -> MailMessageBatch {
        try await batch(mailbox: mailbox,afterNativeID: 0,cutoff: cutoff,limit: limit)
    }
}

/// Fixed JXA code sends only read-only Apple Events. No message read-status, move,
/// send, synchronize, delete, or quit commands. User data is passed as JSON argv.
public struct AppleMailReader: MailReading {
    public init() {}
    private func run(_ operation: String, argument: String = "{}") async throws -> Data {
        let result = try await ProcessRunner().run("/usr/bin/osascript", ["-l", "JavaScript", "-e", Self.script, operation, argument], directory: URL(fileURLWithPath: "/"), timeout: 45, outputLimit: 2_000_000)
        guard result.exitCode == 0, !result.truncated else { throw StoreError(message: "Read-only Mail Automation unavailable: " + String(result.stderr.prefix(1000))) }
        return Data(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
    }
    public func inventory() async throws -> MailInventory { try JSONDecoder().decode(MailInventory.self, from: await run("inventory")) }
    public func batch(mailbox: MailboxDescriptor, afterNativeID: Int, cutoff: Date, limit: Int = 40) async throws -> MailMessageBatch {
        try await requestBatch(mailbox: mailbox,afterNativeID: afterNativeID,cutoff: cutoff,limit: limit,recent: false,financialOnly: false)
    }
    public func recentBatch(mailbox: MailboxDescriptor,cutoff: Date,limit: Int) async throws -> MailMessageBatch {
        try await requestBatch(mailbox: mailbox,afterNativeID: 0,cutoff: cutoff,limit: limit,recent: true,financialOnly: false)
    }
    public func receiptSample(mailbox: MailboxDescriptor,cutoff: Date,limit: Int) async throws -> MailMessageBatch {
        try await requestBatch(mailbox: mailbox,afterNativeID: 0,cutoff: cutoff,limit: limit,recent: true,financialOnly: true)
    }
    private func requestBatch(mailbox: MailboxDescriptor,afterNativeID: Int,cutoff: Date,limit: Int,recent: Bool,financialOnly: Bool) async throws -> MailMessageBatch {
        let object: [String: Any] = ["accountID": mailbox.accountID, "path": mailbox.path, "after": afterNativeID, "cutoff": cutoff.ISO8601Format(), "limit": max(1,min(limit,40)),"recent":recent,"financialOnly":financialOnly]
        let argument = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return try Self.decodeBatch(try await run("batch",argument: argument),mailbox: mailbox)
    }
    static func decodeBatch(_ data: Data,mailbox: MailboxDescriptor) throws -> MailMessageBatch {
        struct Response: Decodable { let messages: [RawMessage]; let next: Int; let complete: Bool; let unavailable: [String] }
        struct RawMessage: Decodable { let sourceID: String; let nativeID: Int; let sender: String; let subject: String; let received: String; let body: String }
        let result = try JSONDecoder().decode(Response.self, from: data)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        let messages = try result.messages.map { raw -> MailMessage in
            guard !raw.sourceID.isEmpty, let date = formatter.date(from: raw.received) ?? fallbackFormatter.date(from: raw.received) else { throw StoreError(message: "Malformed Mail message; checkpoint not advanced") }
            return MailMessage(sourceID: raw.sourceID, nativeID: raw.nativeID, mailboxID: mailbox.id, sender: raw.sender, subject: raw.subject, receivedAt: date, body: raw.body)
        }
        return MailMessageBatch(messages: messages, nextNativeID: result.next, complete: result.complete, unavailable: result.unavailable)
    }
    public static let script = #"""
    function run(argv) {
      const mail=Application('Mail'), operation=argv[0], arg=JSON.parse(argv[1] || '{}');
      const excluded=/(^|[\s\/_-])(junk|trash|deleted messages|deleted items|spam)([\s\/_-]|$)|^(drafts|sent|sent messages|outbox)$/i;
      const boxes=[], unavailable=[]; let visited=0;
      function walk(account, parent, path, depth) {
        if(depth>20 || ++visited>2000) { unavailable.push('Mailbox traversal limit'); return; }
        let children; try { children=parent.mailboxes(); } catch(e) { unavailable.push(account+': '+path.join('/')+': '+e); return; }
        children.forEach(function(box) {
          let name; try { name=box.name(); } catch(e) { unavailable.push(account+': inaccessible mailbox'); return; }
          if(excluded.test(name)) return;
          const next=path.concat([name]);
          boxes.push({id:JSON.stringify([account,next]),accountID:account,path:next});
          walk(account,box,next,depth+1);
        });
      }
      if(operation==='inventory') {
        mail.accounts().forEach(function(account) { try { walk(account.id(),account,[],0); } catch(e) { unavailable.push(String(e)); } });
        try { walk('local',mail,[],0); } catch(e) { unavailable.push('Local mailboxes: '+e); }
        return JSON.stringify({mailboxes:boxes,unavailable:unavailable});
      }
      let parent=arg.accountID==='local' ? mail : mail.accounts.byId(arg.accountID);
      arg.path.forEach(function(name) { parent=parent.mailboxes.byName(name); });
      if(arg.path.some(function(name){return excluded.test(name);})) throw Error('Excluded mailbox');
      const ids=arg.financialOnly ? parent.messages.whose({subject:{_contains:'receipt'}}).id() : parent.messages.id();
      if(ids.length>100000) throw Error('Mailbox exceeds bounded metadata limit; coverage incomplete');
      const ordered=ids.filter(function(id){return id>arg.after;}).sort(arg.recent ? function(a,b){return b-a;} : function(a,b){return a-b;});
      const batch=ordered.slice(0,arg.limit), messages=[];
      batch.forEach(function(id){
        const message=parent.messages.byId(id);
        const received=message.dateReceived();
        if(received<new Date(arg.cutoff)) return;
        const messageID=message.messageId();
        if(!messageID) throw Error('Message lacks source identity; checkpoint retained');
        const sender=String(message.sender()), subject=String(message.subject());
        // Keep unrelated correspondence out of receipt parsing and avoid downloading its bodies.
        const candidate=/receipt|invoice|payment|refund|purchase|order|subscription|billing|charged|renewal|paid|\bbill\b/i.test(subject+' '+sender);
        const body=candidate ? String(message.content()) : '';
        if(body.length>2000000) throw Error('Financial message exceeds read bound; checkpoint retained');
        messages.push({sourceID:messageID,nativeID:id,sender:sender,subject:subject,received:received.toISOString(),body:body.slice(0,24000)});
      });
      return JSON.stringify({messages:messages,next:batch.length?batch[batch.length-1]:arg.after,complete:ordered.length<=arg.limit,unavailable:[]});
    }
    """#
}

public struct MailCollectionProgress: Sendable {
    public var checkedMailboxes = 0
    public var completeMailboxes = 0
    public var committedMessages = 0
    public var pendingPasses = 0
    public var unavailable: [String] = []
    public var complete: Bool { unavailable.isEmpty && checkedMailboxes > 0 && checkedMailboxes == completeMailboxes && pendingPasses == 0 }
}
public actor MailReceiptCollector {
    private let store: IntelligenceStore
    private let reader: any MailReading
    private var busy = false
    public init(store: IntelligenceStore, reader: any MailReading = AppleMailReader()) { self.store = store; self.reader = reader }
    /// Each tick admits bounded batches. A completed pass rechecks the same 12-month window
    /// every 30 minutes, catching moved/reordered messages without trusting mailbox offsets.
    public func collect(now: Date = Date(), maximumBatches: Int = 2, force: Bool = false) async throws -> MailCollectionProgress {
        guard !busy else { throw StoreError(message: "Mail collector already owns an intake") }
        busy = true; defer { busy = false }
        let inventory = try await reader.inventory()
        var progress = MailCollectionProgress(); progress.unavailable = inventory.unavailable
        var budget = max(1,min(maximumBatches,100))
        var pending: [(MailboxDescriptor,MailCheckpoint)] = []
        for mailbox in inventory.mailboxes {
            let checkpoint = try await store.load(MailCheckpoint.self,namespace: "mail-checkpoints",id: mailbox.id) ?? MailCheckpoint(mailboxID: mailbox.id,cutoff: Calendar.current.date(byAdding: .month,value: -12,to: now)!)
            pending.append((mailbox,checkpoint))
        }
        // Seed recent evidence across every mailbox first, then round-robin unfinished
        // backfills before rechecks. A large inbox cannot starve another account.
        pending.sort {
            func rank(_ value: MailCheckpoint) -> Int { !value.recentSeeded ? 0 : (value.completedAt == nil ? 1 : 2) }
            let left = rank($0.1),right = rank($1.1)
            if left != right { return left < right }
            if $0.1.checkedAt != $1.1.checkedAt { return $0.1.checkedAt < $1.1.checkedAt }
            return $0.0.id < $1.0.id
        }
        for (mailbox,saved) in pending {
            try Task.checkCancellation()
            var checkpoint = saved
            progress.checkedMailboxes += 1
            if let completed = checkpoint.completedAt,!checkpoint.inProgress {
                if !force && now.timeIntervalSince(completed) < 1800 { progress.completeMailboxes += 1; continue }
                checkpoint.afterNativeID = 0; checkpoint.inProgress = true; checkpoint.cutoff = Calendar.current.date(byAdding: .month,value: -12,to: now)!
            }
            while budget > 0 && checkpoint.inProgress {
                budget -= 1
                do {
                    let seeding = !checkpoint.recentSeeded
                    let batch = try await (seeding ? reader.recentBatch(mailbox: mailbox,cutoff: checkpoint.cutoff,limit: 40) : reader.batch(mailbox: mailbox, afterNativeID: checkpoint.afterNativeID, cutoff: checkpoint.cutoff, limit: 40))
                    guard batch.unavailable.isEmpty else { progress.unavailable += batch.unavailable; break }
                    guard seeding || batch.complete || batch.nextNativeID > checkpoint.afterNativeID else { throw StoreError(message: "Mail batch made no progress") }
                    var receipts: [ReceiptRecord] = [], processed: [String] = []
                    for message in batch.messages {
                        if try await store.mailProcessed(message.sourceID) { continue }
                        if let receipt = ReceiptParser.parse(message) { receipts.append(receipt) }
                        processed.append(message.sourceID)
                    }
                    if seeding { checkpoint.recentSeeded = true } else { checkpoint.afterNativeID = batch.nextNativeID }
                    checkpoint.processed += processed.count; checkpoint.checkedAt = now
                    if batch.complete && !seeding { checkpoint.completedAt = now; checkpoint.inProgress = false }
                    try Task.checkCancellation()
                    try await store.commitMail(receipts, processedIDs: processed, checkpoint: checkpoint)
                    progress.committedMessages += processed.count
                } catch is CancellationError { throw CancellationError() }
                catch { progress.unavailable.append(mailbox.id + ": " + error.localizedDescription); break }
            }
            if checkpoint.completedAt != nil { progress.completeMailboxes += 1 }
            if checkpoint.inProgress { progress.pendingPasses += 1 }
        }
        if inventory.mailboxes.isEmpty { progress.unavailable.append("No accessible account mailboxes") }
        return progress
    }
}
