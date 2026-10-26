import Foundation
import CSQLite

/// Separate local database: existing history schemas and IDs are unchanged.
/// JSON payloads retain Decimal values; checkpoint updates share the receipt transaction.
public actor IntelligenceStore {
    private let db: Database
    public init(path: String) throws {
        let db = try Database(path: path)
        let version = try db.scalar("PRAGMA user_version")
        guard (0...1).contains(version) else { throw StoreError(message: "Intelligence schema is newer than this Newton build") }
        try db.execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL")
        if version == 0 {
            try db.execute("BEGIN IMMEDIATE")
            do {
                guard try db.scalar("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else { throw StoreError(message: "Unrecognized intelligence database") }
                try db.execute("CREATE TABLE records(namespace TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,PRIMARY KEY(namespace,id)); CREATE TABLE processed_mail(id TEXT PRIMARY KEY NOT NULL); PRAGMA user_version=1")
                try db.execute("COMMIT")
            } catch { try? db.execute("ROLLBACK"); throw error }
        }
        let check = try db.statement("SELECT namespace,id,payload FROM records LIMIT 0"); sqlite3_finalize(check)
        _ = try db.scalar("SELECT count(*) FROM processed_mail")
        self.db = db
    }
    private func put<T: Encodable>(_ value: T, namespace: String, id: String) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 2_000_000, !id.isEmpty, id.utf8.count <= 4096 else { throw StoreError(message: "Intelligence record exceeds local bounds") }
        let statement = try db.statement("INSERT INTO records VALUES(?,?,?) ON CONFLICT(namespace,id) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(statement) }
        try db.bind(namespace, to: statement, at: 1); try db.bind(id, to: statement, at: 2)
        try db.bind(String(decoding: data, as: UTF8.self), to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw db.error() }
    }
    public func save<T: Encodable & Sendable>(_ value: T, namespace: String, id: String) throws { try put(value, namespace: namespace, id: id) }
    public func load<T: Decodable & Sendable>(_ type: T.Type, namespace: String, id: String) throws -> T? {
        let statement = try db.statement("SELECT payload FROM records WHERE namespace=? AND id=?")
        defer { sqlite3_finalize(statement) }; try db.bind(namespace, to: statement, at: 1); try db.bind(id, to: statement, at: 2)
        let status = sqlite3_step(statement)
        if status == SQLITE_DONE { return nil }
        guard status == SQLITE_ROW else { throw db.error() }
        return try JSONDecoder().decode(type, from: Data(db.string(statement, 0).utf8))
    }
    public func list<T: Decodable & Sendable>(_ type: T.Type, namespace: String, limit: Int = 10_000) throws -> [T] {
        let statement = try db.statement("SELECT payload FROM records WHERE namespace=? ORDER BY id LIMIT ?")
        defer { sqlite3_finalize(statement) }; try db.bind(namespace, to: statement, at: 1)
        sqlite3_bind_int(statement, 2, Int32(max(1, min(limit, 50_000)) + 1))
        var result: [T] = []
        while true {
            let status = sqlite3_step(statement); if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW else { throw db.error() }
            result.append(try JSONDecoder().decode(type, from: Data(db.string(statement, 0).utf8)))
        }
        guard result.count <= limit else { throw StoreError(message: "Intelligence query exceeds its bound; coverage incomplete") }
        return result
    }
    public func mailProcessed(_ id: String) throws -> Bool {
        let statement = try db.statement("SELECT 1 FROM processed_mail WHERE id=?"); defer { sqlite3_finalize(statement) }
        try db.bind(id, to: statement, at: 1); let status = sqlite3_step(statement)
        guard status == SQLITE_ROW || status == SQLITE_DONE else { throw db.error() }
        return status == SQLITE_ROW
    }
    public func commitMail(_ records: [ReceiptRecord], processedIDs: [String], checkpoint: MailCheckpoint) throws {
        try Task.checkCancellation(); try db.execute("BEGIN IMMEDIATE")
        do {
            for record in records {
                // A transaction reference can deduplicate messages from multiple mailboxes.
                if try load(ReceiptRecord.self, namespace: "receipts", id: record.id) == nil { try put(record, namespace: "receipts", id: record.id) }
            }
            let statement = try db.statement("INSERT INTO processed_mail VALUES(?) ON CONFLICT(id) DO NOTHING")
            defer { sqlite3_finalize(statement) }
            for id in processedIDs {
                sqlite3_reset(statement); sqlite3_clear_bindings(statement); try db.bind(id, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw db.error() }
            }
            try put(checkpoint, namespace: "mail-checkpoints", id: checkpoint.mailboxID)
            try Task.checkCancellation(); try db.execute("COMMIT")
        } catch { try? db.execute("ROLLBACK"); throw error }
    }
}

extension IntelligenceStore {
    public func recordJobProgress(id: String, phase: AgentPhase, evidence: String, worktree: String?) throws {
        guard var job = try load(AutonomousJob.self,namespace: "jobs",id: id), [.running,.verifying].contains(job.state) else { return }
        if phase == .verifying { job.state = .verifying }
        job.evidence = String(evidence.suffix(40_000)); job.worktree = worktree
        try put(job,namespace: "jobs",id: id)
    }
}

extension IntelligenceStore {
    public func coverageIntervals(from start: Date,to end: Date,openOnly: Bool = false) throws -> [CaptureCoverageRecord] {
        let filter = openOnly ? "json_extract(payload,'$.end') IS NULL" : "CAST(json_extract(payload,'$.start') AS REAL) < ? AND (json_extract(payload,'$.end') IS NULL OR CAST(json_extract(payload,'$.end') AS REAL) >= ?)"
        let statement = try db.statement("SELECT payload FROM records WHERE namespace='coverage' AND \(filter) ORDER BY id LIMIT 50001")
        defer { sqlite3_finalize(statement) }
        if !openOnly { sqlite3_bind_double(statement,1,end.timeIntervalSinceReferenceDate); sqlite3_bind_double(statement,2,start.timeIntervalSinceReferenceDate) }
        var result: [CaptureCoverageRecord] = []
        while true {
            let status = sqlite3_step(statement); if status == SQLITE_DONE { break }; guard status == SQLITE_ROW else { throw db.error() }
            result.append(try JSONDecoder().decode(CaptureCoverageRecord.self,from: Data(db.string(statement,0).utf8)))
        }
        guard result.count <= 50_000 else { throw StoreError(message: "Coverage interval query truncated; report refused") }
        return result
    }
}
