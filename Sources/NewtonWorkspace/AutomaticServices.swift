import AppKit
import Observation
import CryptoKit
import NewtonCore

@MainActor @Observable public final class AutomaticServices {
    public private(set) var states: [NewtonFeature: ServiceLifecycle] = [:]
    public private(set) var receipts: [ReceiptRecord] = []
    public private(set) var renewals: [PredictedRenewal] = []
    public private(set) var latestReport: StoredDailyReport?
    public private(set) var jobs: [AutonomousJob] = []
    public private(set) var repositoryRoots = ""
    public private(set) var transcriptWriteDiagnostic = "No pending transcript writes"
    public private(set) var meetingProposal: String?
    public var detectMeetings = false { didSet { maintainLoop() } }
    public var automaticallyRecordMeetings = false
    public var onMeetingRequested: (@MainActor () -> Void)?
    public var onProjects: (@MainActor ([TrackedProject]) -> Void)?
    public var onState: (@MainActor (NewtonFeature,ServiceLifecycle) -> Void)?
    @ObservationIgnored private var acceptanceURL: URL?
    @ObservationIgnored private var binarySHA256 = ""
    @ObservationIgnored private var store: IntelligenceStore?
    @ObservationIgnored private var mail: MailReceiptCollector?
    @ObservationIgnored private var reports: DailyReportService?
    @ObservationIgnored private var context: RepositoryContextCache?
    @ObservationIgnored private var queue: AutonomousAgentQueue?
    @ObservationIgnored private var enabled = Set<NewtonFeature>()
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var loop: Task<Void,Never>?
    @ObservationIgnored private var mailTask: Task<Void,Never>?
    @ObservationIgnored private var reportTask: Task<Void,Never>?
    @ObservationIgnored private var projectTask: Task<Void,Never>?
    @ObservationIgnored private var queueTask: Task<Void,Never>?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var lastMail = Date.distantPast
    @ObservationIgnored private var lastProjects = Date.distantPast
    @ObservationIgnored private var lastReportDay: Date?
    @ObservationIgnored private var reportDirty = true
    @ObservationIgnored private var projects: [TrackedProject] = []
    @ObservationIgnored private var coverage: [String:CaptureCoverageRecord] = [:]
    @ObservationIgnored private var pendingTranscripts: [MeetingTranscriptRecord] = []
    public var isAvailable: Bool { store != nil }
    @ObservationIgnored private var transcriptTask: Task<Void,Never>?
    @ObservationIgnored private var coverageTask: Task<Void,Never>?
    public init() {}
    public func open(history: any HistoryRepository, directory: URL, repository: URL) async throws {
        guard store == nil else { return }
        let store = try await Task.detached(priority: .utility) { try IntelligenceStore(path: directory.appendingPathComponent("intelligence.sqlite").path) }.value
        acceptanceURL = directory.appendingPathComponent("rollout-acceptance.json")
        if let executable = Bundle.main.executableURL {
            binarySHA256 = await Task.detached(priority: .utility) {
                (try? Data(contentsOf: executable)).map { SHA256.hash(data: $0).map { String(format: "%02x",$0) }.joined() } ?? ""
            }.value
        }
        self.store = store; mail = MailReceiptCollector(store: store); reports = DailyReportService(history: history,store: store)
        context = RepositoryContextCache(store: store); queue = AutonomousAgentQueue(store: store,repository: repository)
        try await queue?.recoverInterrupted()
        repositoryRoots = try await context!.roots().joined(separator: "\n")
        receipts = try await store.list(ReceiptRecord.self,namespace: "receipts")
        renewals = ReceiptRecurrence.predictions(receipts)
        latestReport = try await store.list(StoredDailyReport.self,namespace: "reports").max { $0.generatedAt < $1.generatedAt }
        jobs = try await queue!.jobs()
        // Close interrupted source intervals explicitly; do not invent continuous coverage.
        for var record in try await store.coverageIntervals(from: .distantPast,to: Date(),openOnly: true) {
            record.end = record.start; try await store.save(record,namespace: "coverage",id: record.id)
        }
    }
    public func recordCoverage(source: String,state: String,reason: String) {
        guard let store else { return }
        let now = Date()
        if coverage[source]?.state == state && coverage[source]?.reason == reason { return }
        var previous = coverage[source]; previous?.end = now
        let record = CaptureCoverageRecord(source: source,state: state,reason: reason,at: now)
        coverage[source] = record
        let preceding = coverageTask
        coverageTask = Task {
            await preceding?.value
            do {
                if let previous { try await store.save(previous,namespace: "coverage",id: previous.id) }
                try await store.save(record,namespace: "coverage",id: record.id)
            } catch { self.update(.dailyReports,.failed,"Coverage journal could not be saved: " + error.localizedDescription) }
        }
        reportDirty = true
    }
    public func historyChanged() { reportDirty = true }
    private func update(_ feature: NewtonFeature,_ phase: ServicePhase,_ reason: String, success: Date? = nil) {
        let state = ServiceLifecycle(phase,reason: reason,lastSuccessfulActivity: success ?? states[feature]?.lastSuccessfulActivity)
        states[feature] = state; onState?(feature,state)
        recordCoverage(source: feature.rawValue,state: phase.rawValue,reason: reason)
    }
    public func setEnabled(_ feature: NewtonFeature,_ value: Bool) throws {
        guard store != nil else { throw StoreError(message: "Automatic local storage unavailable") }
        if value { enabled.insert(feature); update(feature,.starting,"Waiting for local source preflight") }
        else {
            enabled.remove(feature); update(feature,.disabled,"Disabled")
            switch feature {
            case .mailFinance: mailTask?.cancel()
            case .dailyReports: reportTask?.cancel()
            case .projectContext: projectTask?.cancel()
            case .overnightAgents: queueTask?.cancel(); Task { await queue?.cancel() }
            default: break
            }
        }
        maintainLoop()
        tick()
    }
    private func maintainLoop() {
        if enabled.isEmpty && !detectMeetings { loop?.cancel(); loop = nil }
        else if loop == nil { loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        } }
    }
    public func setSuspended(_ value: Bool) {
        suspended = value
        if value {
            epoch = UUID(); mailTask?.cancel(); reportTask?.cancel(); projectTask?.cancel(); queueTask?.cancel()
            Task { await queue?.cancel() }
            for feature in enabled { update(feature,.paused,"Pause All, lock or sleep") }
        } else { lastMail = .distantPast; tick() }
    }
    public func stop() async throws {
        setSuspended(true); loop?.cancel(); loop = nil
        await queue?.cancel(); await mailTask?.value; await reportTask?.value; await projectTask?.value; await queueTask?.value
        startTranscriptDrain(); await transcriptTask?.value
        guard pendingTranscripts.isEmpty else { throw StoreError(message: "Full transcripts remain unsaved; retry before quitting") }
        await coverageTask?.value
        for (key,var record) in coverage { record.end = Date(); try? await store?.save(record,namespace: "coverage",id: record.id); coverage.removeValue(forKey: key) }
    }
    public func recordTranscript(_ record: MeetingTranscriptRecord) {
        pendingTranscripts.append(record); transcriptWriteDiagnostic = "Saving full transcript locally"; startTranscriptDrain()
    }
    public func retryTranscriptWrites() async { startTranscriptDrain(); await transcriptTask?.value }
    private func startTranscriptDrain() {
        guard transcriptTask == nil,let store,!pendingTranscripts.isEmpty else { return }
        transcriptTask = Task {
            defer { transcriptTask = nil }
            while let record = pendingTranscripts.first {
                do {
                    try await store.save(record,namespace: "transcripts",id: record.id.uuidString)
                    pendingTranscripts.removeFirst()
                } catch {
                    transcriptWriteDiagnostic = "Full transcript retained for retry: " + error.localizedDescription
                    recordCoverage(source: "transcript writes",state: "failed",reason: transcriptWriteDiagnostic); return
                }
            }
            transcriptWriteDiagnostic = "Full transcripts saved locally"
        }
    }
    public func saveRoots(_ text: String) async {
        do { try await context?.setRoots(text.split(separator: "\n").map(String.init)); repositoryRoots = text; lastProjects = .distantPast; tick() }
        catch { update(.projectContext,.failed,error.localizedDescription) }
    }
    public func checkMeetingApplication() {
        guard detectMeetings, !suspended else { meetingProposal = nil; return }
        let supported = ["us.zoom.xos","com.microsoft.teams2","com.microsoft.teams","com.apple.FaceTime"]
        if let app = NSWorkspace.shared.runningApplications.first(where: { supported.contains($0.bundleIdentifier ?? "") }) {
            let proposed = app.localizedName ?? "Meeting app"
            if meetingProposal != proposed { meetingProposal = proposed; if automaticallyRecordMeetings { onMeetingRequested?() } }
        } else { meetingProposal = nil }
    }
    public func tick(now: Date = Date()) {
        checkMeetingApplication()
        guard !suspended else { return }
        let generation = epoch
        if enabled.contains(.mailFinance), mailTask == nil, now.timeIntervalSince(lastMail) >= 60, let mail {
            lastMail = now
            mailTask = Task { [weak self] in
                defer { self?.mailTask = nil }
                do {
                    let result = try await mail.collect(now: now)
                    guard let self,!Task.isCancelled,self.epoch == generation,self.enabled.contains(.mailFinance),let store = self.store else { return }
                    self.receipts = try await store.list(ReceiptRecord.self,namespace: "receipts"); self.renewals = ReceiptRecurrence.predictions(self.receipts)
                    self.update(.mailFinance,result.complete ? .running : .blocked,"\(result.completeMailboxes)/\(result.checkedMailboxes) mailboxes backfilled · \(result.pendingPasses) pending passes · \(result.committedMessages) newly indexed · " + result.unavailable.joined(separator: "; "),success: now)
                } catch { if !Task.isCancelled { self?.update(.mailFinance,.blocked,error.localizedDescription) } }
            }
        }
        if enabled.contains(.projectContext), projectTask == nil, now.timeIntervalSince(lastProjects) >= 1800, let context {
            lastProjects = now
            projectTask = Task { [weak self] in
                defer { self?.projectTask = nil }
                do {
                    let projects = try await context.refresh()
                    guard let self,!Task.isCancelled,self.epoch == generation,self.enabled.contains(.projectContext) else { return }
                    self.projects = projects; self.onProjects?(projects)
                    self.update(.projectContext,.running,"\(projects.count) recently inspected repositories; foreground project unknown",success: now)
                } catch { if !Task.isCancelled { self?.update(.projectContext,.failed,error.localizedDescription) } }
            }
        }
        if enabled.contains(.dailyReports), reportTask == nil, let range = DailyReportService.dueRange(now: now), (lastReportDay != range.start || reportDirty), let reports {
            reportDirty = false
            reportTask = Task { [weak self] in
                defer { self?.reportTask = nil }
                do {
                    let report = try await reports.generateIfDue(now: now,projects: self?.projects ?? [])
                    guard let self,!Task.isCancelled,self.epoch == generation,self.enabled.contains(.dailyReports) else { return }
                    self.latestReport = report; self.lastReportDay = range.start
                    self.update(.dailyReports,.running,"08:15 daily summary saved locally; source gaps recorded",success: now)
                } catch { if !Task.isCancelled { self?.reportDirty = true; self?.update(.dailyReports,.failed,error.localizedDescription) } }
            }
        }
        if enabled.contains(.overnightAgents), queueTask == nil, let queue {
            queueTask = Task { [weak self] in
                defer { self?.queueTask = nil }
                do {
                    // Accepted rollout gates are durable and separate from the user's opt-in.
                    guard let self,let acceptanceURL = self.acceptanceURL else { return }
                    if let reason = RolloutAcceptance.read(from: acceptanceURL,currentBinarySHA256: self.binarySHA256) {
                        self.update(.overnightAgents,.blocked,reason + "; no job admitted"); return
                    }
                    try await queue.ingestCommittedBacklog()
                    let quota = await CodexQuotaReader.readSnapshotAsync().quota
                    guard !Task.isCancelled,self.epoch == generation else { return }
                    let power = PowerPacingEngine.captureSnapshot()
                    let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType: CGEventType(rawValue: UInt32.max)!)
                    let environment = AutonomousEnvironment(now: now,unlocked: !self.suspended,externallyPowered: power.isPluggedIn == true,acceptableThermalState: ["Nominal","Fair"].contains(power.thermalState),idleSeconds: idle,quota: quota)
                    if await queue.isRunning, let reason = environment.executionDenial() {
                        await queue.cancel(); self.update(.overnightAgents,.paused,reason); return
                    }
                    let reason = try await queue.tick(environment)
                    self.jobs = try await queue.jobs(); self.update(.overnightAgents,.running,reason,success: now)
                } catch { if !Task.isCancelled { self?.update(.overnightAgents,.blocked,error.localizedDescription) } }
            }
        }
    }
}
