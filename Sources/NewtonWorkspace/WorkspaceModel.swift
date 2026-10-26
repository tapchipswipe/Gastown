import AppKit
import Observation
import NewtonCore
import UniformTypeIdentifiers

@MainActor @Observable
public final class WorkspaceModel {
    @ObservationIgnored public var presentationCommand: (@MainActor (WorkspacePresentationCommand) -> Void)?
    @ObservationIgnored public var openWorkspace: (@MainActor () -> Void)?
    public var requestedSection: String?
    public var requestedReport: String?
    public private(set) var focusShieldActive = false
    @ObservationIgnored private var focusPanels: [NSPanel] = []
    @ObservationIgnored private var focusAwake: (any WakePreventing)?
    public var captureExcludedApps = "" {
        didSet {
            if restorePreferences && directory == Self.dataDirectory { UserDefaults.standard.set(captureExcludedApps.split(separator: "\n").map(String.init), forKey: "Newton.captureExcludedBundleIDs") }
            if oldValue != captureExcludedApps,enabled.contains(.screenOCR),!readingPreferences {
                applyFeature(.screenOCR,enabled: false)
                if suspensionReasons.isEmpty { applyFeature(.screenOCR,enabled: true) }
            }
            savePreferences()
        }
    }
    public var focusShieldKeepsAwake = false
    public func setProtectedApplications(_ text: String) {
        let ids = Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        guard ids.count <= 100,ids.allSatisfy({ $0.contains(".") && $0.utf8.count <= 255 && $0.range(of: "^[A-Za-z0-9_.-]+$",options: .regularExpression) != nil }) else { errorMessage = "Enter at most 100 valid bundle identifiers"; return }
        QuitProtectionEngine.shared.config.protectedBundleIDs = ids; savePreferences()
    }
    public func setHoldDuration(_ duration: Double) {
        guard duration.isFinite else { return }; QuitProtectionEngine.shared.config.holdDurationSeconds = min(2,max(0.2,duration)); savePreferences()
    }
    public func setCleaningScreenVisible(_ value: Bool) { CleaningModeEngine.shared.keepScreenVisible = value; savePreferences() }
    public func setFocusShieldWake(_ value: Bool) {
        let active = focusShieldActive; if active { setFocusShield(false) }
        focusShieldKeepsAwake = value; if active { setFocusShield(true,keepAwake: value) }; savePreferences()
    }
    public func setQuitProtection(_ value: Bool) { keyboard.setQuitProtection(value); savePreferences() }
    public func perform(_ command: WorkspaceCommand) {
        switch command {
        case .presentation(let command): presentationCommand?(command)
        case .pauseAll: pauseAll()
        case .resumeAll: resumeAll()
        case .toggleAwake: toggle(.keepAwake, enabled: !enabled.contains(.keepAwake))
        case .toggleCleaning:
            if keyboard.cleaningActive { keyboard.stopCleaning() }
            else if !keyboard.startCleaning() { errorMessage = keyboard.state.reason }
        case .toggleQuitProtection: setQuitProtection(!keyboard.quitEnabled)
        case .toggleFocusShield: setFocusShield(!focusShieldActive,keepAwake: focusShieldKeepsAwake)
        case .scanCleanup: _ = runMasterTurboSweep(); requestedSection = "Utilities & Clean"; openWorkspace?()
        case .navigate(let section): requestedSection = section; openWorkspace?()
        case .report(let report): requestedReport = report; requestedSection = "Pipes & SOPs"; openWorkspace?()
        case .snap(let action):
            if !WindowSnapEngine.shared.snapFrontmostWindow(to: action) { errorMessage = "Window snapping unavailable; check Accessibility permission and the focused window." }
        }
    }
    /// A dimming overlay with an independently owned optional idle-sleep assertion.
    public func setFocusShield(_ value: Bool, keepAwake: Bool = false) {
        if !value {
            for panel in focusPanels { panel.orderOut(nil) }; focusPanels = []
            do { try focusAwake?.stop(); focusAwake = nil } catch { errorMessage = error.localizedDescription }
            focusShieldActive = false; return
        }
        guard !focusShieldActive, suspensionReasons.isEmpty, !isStopping else { return }
        do {
            if keepAwake { let service = wakeFactory(); try service.start(); focusAwake = service }
            for screen in NSScreen.screens {
                let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.backgroundColor = NSColor.black.withAlphaComponent(0.30); panel.isOpaque = false
                panel.ignoresMouseEvents = true; panel.level = .floating
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
                panel.orderFrontRegardless(); focusPanels.append(panel)
            }
            focusShieldActive = true
        } catch { errorMessage = error.localizedDescription }
    }
    public let automation = AutomaticServices()
    public let systemSpeech = SystemAudioTranscriber()
    public var includeSystemAudio = false
    public let speech = SpeechTranscriptionEngine()
    public let keyboard = KeyboardProtectionService()
    public private(set) var serviceStates: [NewtonFeature: ServiceLifecycle] = [:]
    public private(set) var selectedFeatures = Set<NewtonFeature>()
    public private(set) var isPaused = false
    public private(set) var setupComplete = false
    @ObservationIgnored private var suspensionReasons = Set<String>()
    @ObservationIgnored private var systemLifecycle: WorkspaceSystemLifecycle?
    @ObservationIgnored private var restorePreferences = false
    @ObservationIgnored private var readingPreferences = false
    @ObservationIgnored private var preferencesURL: URL { directory.appendingPathComponent("capabilities.json") }

    public func startMeeting() async {
        guard ready, suspensionReasons.isEmpty, !isStopping, !deleteBusy else { return }
        guard automation.isAvailable else { errorMessage = "Local transcript storage unavailable"; return }
        speech.onRecord = { [weak self] record in
            guard let self else { return }; self.persistTranscript(record)
            Task { await self.systemSpeech.stop() }
        }
        systemSpeech.onRecord = { [weak self] record in
            guard let self else { return }; self.persistTranscript(record)
            if self.speech.isRecording { self.speech.stopLiveMeeting() }
        }
        await speech.requestPermissionsAndStart { [weak self] in
            guard let self else { return false }; return self.suspensionReasons.isEmpty && !self.isStopping && !self.deleteBusy
        }
        if !suspensionReasons.isEmpty || isStopping { speech.stopLiveMeeting() }
        else if includeSystemAudio && speech.isRecording {
            await systemSpeech.start { [weak self] in self?.speech.isRecording == true && self?.suspensionReasons.isEmpty == true }
        }
    }
    private func persistTranscript(_ record: MeetingTranscriptRecord) {
        automation.recordTranscript(record)
        for segment in record.segments {
            let characters = Array(segment.text)
            for start in stride(from: 0,to: characters.count,by: 6000) {
                let text = String(characters[start..<min(start+6000,characters.count)])
                acceptCaptureEvent(HistoryEvent(id: "transcript:" + segment.id.uuidString + ":\(start/6000)",timestamp: segment.timestamp,source: "Newton · " + segment.sourceChannel + " transcript",title: record.meetingTitle,detail: (segment.isFinal ? "Final: " : "Unfinalized hypothesis: ") + text))
            }
        }
    }
    public func stopMeeting() { speech.stopLiveMeeting(); Task { await systemSpeech.stop() } }
    public func saveMeetingPreferences() { savePreferences() }
    public func completeSetup() { setupComplete = true; savePreferences() }
    private func savePreferences() {
        guard restorePreferences,!readingPreferences else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["setupComplete": setupComplete, "selected": selectedFeatures.map(\.rawValue).sorted(), "paused": isPaused, "quitProtection": keyboard.quitEnabled, "captureExcludedApps": captureExcludedApps, "detectMeetings": automation.detectMeetings, "autoRecordMeetings": automation.automaticallyRecordMeetings, "includeSystemAudio": includeSystemAudio, "protectedApplications": Array(QuitProtectionEngine.shared.config.protectedBundleIDs).sorted(), "holdDuration": QuitProtectionEngine.shared.config.holdDurationSeconds, "cleaningScreenVisible": CleaningModeEngine.shared.keepScreenVisible, "focusShieldKeepsAwake": focusShieldKeepsAwake])
            try data.write(to: preferencesURL, options: [.atomic])
        } catch { errorMessage = "Capability choices could not be saved: " + error.localizedDescription }
    }
    private func loadPreferences() {
        guard restorePreferences, let data = try? Data(contentsOf: preferencesURL) else { return }
        readingPreferences = true
        defer { readingPreferences = false }
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let selected = object["selected"] as? [String] else { throw StoreError(message: "Invalid capability preferences") }
            setupComplete = object["setupComplete"] as? Bool ?? false
            if let ids = object["protectedApplications"] as? [String] { setProtectedApplications(ids.joined(separator: "\n")) }
            if let duration = object["holdDuration"] as? Double { setHoldDuration(duration) }
            CleaningModeEngine.shared.keepScreenVisible = object["cleaningScreenVisible"] as? Bool ?? false
            focusShieldKeepsAwake = object["focusShieldKeepsAwake"] as? Bool ?? false
            captureExcludedApps = object["captureExcludedApps"] as? String ?? ""
            includeSystemAudio = object["includeSystemAudio"] as? Bool ?? false
            automation.detectMeetings = object["detectMeetings"] as? Bool ?? false
            automation.automaticallyRecordMeetings = object["autoRecordMeetings"] as? Bool ?? false
            selectedFeatures = Set(selected.compactMap(NewtonFeature.init(rawValue:)))
            if object["paused"] as? Bool == true { isPaused = true; suspensionReasons.insert("Pause All") }
            automation.setSuspended(!suspensionReasons.isEmpty)
        keyboard.setSuspended(!suspensionReasons.isEmpty)
            if object["quitProtection"] as? Bool == true { keyboard.setQuitProtection(true) }
            if setupComplete && suspensionReasons.isEmpty {
                for feature in selectedFeatures { applyFeature(feature, enabled: true) }
            }
        } catch { errorMessage = "Capability preferences unavailable: " + error.localizedDescription }
    }
    public func toggle(_ feature: NewtonFeature, enabled value: Bool) {
        guard ready, !isStopping else { return }
        if value { selectedFeatures.insert(feature) } else { selectedFeatures.remove(feature) }
        if suspensionReasons.isEmpty || !value { applyFeature(feature, enabled: value) }
        else { serviceStates[feature] = ServiceLifecycle(.paused, reason: suspensionReasons.sorted().joined(separator: ", ")) }
        savePreferences()
    }
    public func pauseAll() { isPaused = true; setSuspended(true, reason: "Pause All"); savePreferences() }
    public func resumeAll() { isPaused = false; setSuspended(false, reason: "Pause All"); savePreferences() }
    public func setSuspended(_ suspended: Bool, reason: String) {
        if suspended { suspensionReasons.insert(reason) } else { suspensionReasons.remove(reason) }
        if !suspensionReasons.isEmpty { setFocusShield(false) }
        if !suspensionReasons.isEmpty { stopMeeting() }
        automation.setSuspended(!suspensionReasons.isEmpty)
        keyboard.setSuspended(!suspensionReasons.isEmpty)
        if !suspensionReasons.isEmpty {
            for feature in Array(enabled) { applyFeature(feature, enabled: false) }
            for feature in selectedFeatures { serviceStates[feature] = ServiceLifecycle(.paused, reason: suspensionReasons.sorted().joined(separator: ", "), lastSuccessfulActivity: serviceStates[feature]?.lastSuccessfulActivity) }
            if isRecordingWorkflow { recordingID = UUID(); pendingWorkflow = workflowRecorder.stop(); isRecordingWorkflow = false }
            cancelAgent()
        } else if ready && !isStopping {
            for feature in selectedFeatures { applyFeature(feature, enabled: true) }
        }
    }

    public private(set) var events: [HistoryEvent] = []
    public private(set) var totalEvents = 0
    public private(set) var cleanupScan = CleanupScan()
    public private(set) var cleanupOutcomes: [CleanupOutcome] = []
    public private(set) var cleanupBusy = false
    public private(set) var cleanupDiagnostic: String?
    @ObservationIgnored private let cleanupService: DeveloperProjectTrimmer
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?

    public var timelineDate = Date() { didSet { if timelineDate != oldValue { clearTimeline(); requestTimeline() } } }
    public private(set) var timeline: [TimeMachineFrame] = []
    public private(set) var timelineSummary = TimeMachineEngine.summarize(timeline: [])
    public private(set) var timelineBusy = false
    public private(set) var timelineError: String?
    public private(set) var timelineComplete = true
    @ObservationIgnored private var timelineClients = 0
    @ObservationIgnored private var timelineGeneration = UUID()
    @ObservationIgnored private var timelineTask: Task<Void, Never>?
    @ObservationIgnored private var timelineRefreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastTimelineRequest = Date.distantPast

    public var query = "" { didSet { if query != oldValue { generation += 1; nextCursor = nil; scheduleSearch() } } }
    public var screenpipeQuery = "" { didSet { if screenpipeQuery != oldValue { cancelScreenpipe(); screenpipeResults = [] } } }
    public private(set) var enabled = Set<NewtonFeature>()
    public private(set) var status = "Opening local history…"
    public var errorMessage: String?
    public private(set) var screenpipeResults: [HistoryEvent] = []
    public var apiToken = "" { didSet { if apiToken != oldValue { cancelScreenpipe(); screenpipeResults = [] } } }
    public private(set) var screenpipeBusy = false
    public private(set) var ocrState: OCRCaptureState = .stopped
    @ObservationIgnored private let ocrCapture: any ScreenOCRCapturing
    @ObservationIgnored private var ocrEpoch = UUID()

    public private(set) var importBusy = false
    public private(set) var deleteBusy = false
    public private(set) var historyBusy = false
    public private(set) var loadingMore = false
    public private(set) var ready = false
    public private(set) var opening = false
    public private(set) var isStopping = false
    public private(set) var pendingWriteCount = 0
    public private(set) var writeFailed = false
    public private(set) var hasMoreHistory = false
    public private(set) var codexQuota: CodexQuota?
    public private(set) var quotaDiagnostic = "Quota snapshot not loaded"
    public var quotaDescription: String { QuotaSnapshot(quota: codexQuota, diagnostic: quotaDiagnostic).description(at: quotaNow()) }
    @ObservationIgnored private let quotaNow: @MainActor () -> Date
    public var scheduleMode: AIScheduleMode { scheduler.currentMode() }
    public private(set) var trackedProjects: [TrackedProject] = []
    public private(set) var activeAgentStatus: AgentTaskStatus?
    public private(set) var isRecordingWorkflow = false
    public private(set) var pendingWorkflow: WorkflowSession?
    public private(set) var workflowExportBusy = false
    @ObservationIgnored private var recordingID = UUID()
    @ObservationIgnored private var workflowBundle: URL?
    @ObservationIgnored private var workflowExportTask: Task<String?, Never>?
    @ObservationIgnored private let workflowExporter: @Sendable (WorkflowSession, URL) async throws -> URL

    @ObservationIgnored private let quotaLoader: @Sendable () async -> QuotaSnapshot
    @ObservationIgnored private let projectLoader: @Sendable () async -> [TrackedProject]
    @ObservationIgnored private var quotaTask: Task<Void, Never>?
    @ObservationIgnored private var projectTask: Task<Void, Never>?
    @ObservationIgnored private var quotaID = UUID()
    @ObservationIgnored private var projectID = UUID()
    @ObservationIgnored private let scheduler = AIScheduler()
    public var agentRepositoryPath = ProcessInfo.processInfo.environment["NEWTON_REPOSITORY"] ?? ""
    public private(set) var lastIdeaDestination: String?
    @ObservationIgnored private let manualAgent: any ManualAgentRunning
    @ObservationIgnored private var agentTask: Task<AgentTaskStatus, Never>?
    @ObservationIgnored private var agentID: UUID?
    @ObservationIgnored private var agentCancelling = false
    @ObservationIgnored private var pendingAgentProgress: AgentTaskStatus?
    @ObservationIgnored private var agentProgressTask: Task<Void, Never>?
    @ObservationIgnored private let ideasDirectory: @Sendable () -> URL
    @ObservationIgnored private let atlasDirectory: @Sendable () -> URL
    @ObservationIgnored private let fileIntake: @Sendable (FileIntakeRequest) async throws -> FileIntakeResult
    @ObservationIgnored private var ideaRetry: (title: String, detail: String, url: URL)?
    @ObservationIgnored private let workflowRecorder: any WorkflowRecording

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let storeFactory: @Sendable () async throws -> any HistoryRepository
    @ObservationIgnored private let activityFactory: @MainActor () -> any ActivityMonitoring
    @ObservationIgnored private let wakeFactory: @MainActor () -> any WakePreventing
    @ObservationIgnored private let connector: any ScreenpipeSearching
    @ObservationIgnored private let importLoader: @Sendable (URL) async throws -> ImportBatch
    @ObservationIgnored private var store: (any HistoryRepository)?
    @ObservationIgnored private var activity: (any ActivityMonitoring)?
    @ObservationIgnored private var awake: (any WakePreventing)?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Bool, Never>?
    @ObservationIgnored private var ingestTask: Task<Void, Never>?
    @ObservationIgnored private var shutdownTask: Task<Void, any Error>?
    @ObservationIgnored private var importWriting = false
    @ObservationIgnored private var importPanel: NSOpenPanel?
    @ObservationIgnored private var remoteID: UUID?
    @ObservationIgnored private var importID: UUID?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var countGeneration = 0
    @ObservationIgnored private var activityEpoch = UUID()
    @ObservationIgnored private var pendingEvents: [HistoryEvent] = []
    @ObservationIgnored private var nextCursor: HistoryCursor?
    @ObservationIgnored private var presentationVisible = true
    @ObservationIgnored private var historyClients = 0

    public static var dataDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["NEWTON_DATA_DIRECTORY"] { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Newton")
    }
    // Keep the live no-argument construction inside this module. Swift 6.1 can
    // crash lowering cross-module actor-isolated default closures in NSObject properties.
    public convenience init() {
        self.init(directory: Self.dataDirectory, storeFactory: nil,
                  activityFactory: { ActivityService() }, wakeFactory: { KeepAwakeService() },
                  connector: ScreenpipeClient(), importLoader: nil,
                  workflowRecorder: ScreenActionCaptureService(),
                  quotaLoader: { await CodexQuotaReader.readSnapshotAsync() },
                  projectLoader: { await ProjectAtlasScanner.scanProjects() },
                  ideasDirectory: { iCloudIdeaStore.resolveIdeasDirectory() },
                  atlasDirectory: { TimeAtlasReader.defaultICloudDirectory })
        restorePreferences = true
        systemLifecycle = WorkspaceSystemLifecycle { [weak self] suspended, reason in self?.setSuspended(suspended, reason: reason) }
    }
    public init(directory: URL = WorkspaceModel.dataDirectory,
                storeFactory: (@Sendable () async throws -> any HistoryRepository)? = nil,
                activityFactory: @escaping @MainActor () -> any ActivityMonitoring = { ActivityService() },
                wakeFactory: @escaping @MainActor () -> any WakePreventing = { KeepAwakeService() },
                connector: any ScreenpipeSearching = ScreenpipeClient(),
                importLoader: (@Sendable (URL) async throws -> ImportBatch)? = nil,
                cleanupService: DeveloperProjectTrimmer = DeveloperProjectTrimmer(),
                ocrCapture: any ScreenOCRCapturing = ScreenOCRService(),
                workflowRecorder: any WorkflowRecording = ScreenActionCaptureService(),
                quotaLoader: @escaping @Sendable () async -> QuotaSnapshot = { await CodexQuotaReader.readSnapshotAsync() },
                projectLoader: @escaping @Sendable () async -> [TrackedProject] = { await ProjectAtlasScanner.scanProjects() },
                quotaNow: @escaping @MainActor () -> Date = { Date() },
                ideasDirectory: (@Sendable () -> URL)? = nil,
                atlasDirectory: (@Sendable () -> URL)? = nil,
                manualAgent: any ManualAgentRunning = AgentDispatcher.shared,
                fileIntake: @escaping @Sendable (FileIntakeRequest) async throws -> FileIntakeResult = { try await FileIntake.load($0) },
                persistCapabilities: Bool = false,
                workflowExporter: @escaping @Sendable (WorkflowSession, URL) async throws -> URL = { session, directory in
                    try await Task.detached(priority: .utility) { try WorkflowExporter.save(session, in: directory) }.value
                }) {
        self.cleanupService = cleanupService
        self.ocrCapture = ocrCapture
        self.quotaNow = quotaNow
        self.ideasDirectory = ideasDirectory ?? { directory.appendingPathComponent("Ideas") }
        self.atlasDirectory = atlasDirectory ?? { directory.appendingPathComponent("TimeAtlas") }
        self.manualAgent = manualAgent; self.fileIntake = fileIntake
        self.quotaLoader = quotaLoader; self.projectLoader = projectLoader
        self.directory = directory
        self.activityFactory = activityFactory; self.wakeFactory = wakeFactory; self.connector = connector
        self.workflowRecorder = workflowRecorder; self.workflowExporter = workflowExporter
        self.storeFactory = storeFactory ?? {
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw StoreError(message: "Newton data location must be a regular directory, not a symbolic link.") }
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
                return try EventStore(path: directory.appendingPathComponent("history.sqlite").path)
            }.value
        }
        self.restorePreferences = persistCapabilities
        self.importLoader = importLoader ?? { url in
            let worker = Task.detached(priority: .utility) { try LumenImport.read(url) }
            return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        }
    }

    public func open() async {
        guard !ready, !opening, !isStopping else { return }
        opening = true; status = "Opening local history…"
        defer { opening = false }
        do {
            let opened = try await storeFactory()
            guard !isStopping else { return }
            store = opened; ready = true; status = "Ready · recording is off"
            await refresh()
            if restorePreferences {
                do {
                    try await automation.open(history: opened,directory: directory,repository: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("newton"))
                    automation.onState = { [weak self] feature,state in self?.serviceStates[feature] = state }
                    automation.onProjects = { [weak self] in self?.trackedProjects = $0 }
                    automation.onMeetingRequested = { [weak self] in Task { await self?.startMeeting() } }
                } catch { errorMessage = "Automatic local services unavailable: " + error.localizedDescription }
            }
            loadPreferences()
            requestTimeline(); refreshQuota(); refreshProjectAtlas()
        } catch { status = "Local history unavailable · retry opening"; report(error) }
    }

    private func applyFeature(_ feature: NewtonFeature, enabled value: Bool) {
        guard ready, enabled.contains(feature) != value, !value || (!isStopping && !deleteBusy) else { return }
        serviceStates[feature] = ServiceLifecycle(value ? .starting : .disabled, reason: value ? "Starting" : "Disabled", lastSuccessfulActivity: serviceStates[feature]?.lastSuccessfulActivity)
        do {
            if value {
                switch feature {
                case .mailFinance,.dailyReports,.projectContext,.overnightAgents:
                    try automation.setEnabled(feature,true); enabled.insert(feature)
                case .activity:
                    guard !writeFailed, pendingEvents.count < 4096 else { throw StoreError(message: "Save pending events before restarting activity capture.") }
                    let service = activityFactory(); activity = service
                    service.onCoverage = { [weak self] phase,reason in
                        guard let self else { return }
                        self.serviceStates[.activity] = ServiceLifecycle(phase,reason: reason,lastSuccessfulActivity: self.serviceStates[.activity]?.lastSuccessfulActivity)
                        self.automation.recordCoverage(source: "activity",state: phase.rawValue,reason: reason)
                    }
                    activityEpoch = UUID(); let epoch = activityEpoch
                    enabled.insert(feature)
                    service.start { [weak self] event in
                        guard let self, self.activityEpoch == epoch, self.enabled.contains(.activity), !self.isStopping else { return }
                        guard !self.captureExcludedApps.split(separator: "\n").contains(Substring(event.detail)) else {
                            self.serviceStates[.activity] = ServiceLifecycle(.blocked,reason: "Selected app excluded")
                            self.automation.recordCoverage(source: "activity",state: "blocked",reason: "Selected app excluded"); return
                        }
                        self.acceptCaptureEvent(event)
                    }
                case .keepAwake:
                    let service = wakeFactory(); try service.start(); awake = service; enabled.insert(feature)
                case .screenOCR:
                    guard !writeFailed, pendingEvents.count < 4096 else { throw StoreError(message: "Save pending events before starting OCR.") }
                    ocrEpoch = UUID(); let epoch = ocrEpoch
                    enabled.insert(feature); ocrState = .starting
                    ocrCapture.start(onState: { [weak self] state in
                        guard let self, self.ocrEpoch == epoch, self.enabled.contains(.screenOCR), !self.isStopping else { return }
                        self.ocrState = state
                        self.automation.recordCoverage(source: "screenOCR",state: state.description,reason: state.description)
                        switch state {
                        case .capturing: self.serviceStates[.screenOCR] = ServiceLifecycle(.running, reason: "Main-display text only", lastSuccessfulActivity: Date())
                        case .blocked(let reason): self.serviceStates[.screenOCR] = ServiceLifecycle(.blocked,reason: reason)
                        case .paused: self.serviceStates[.screenOCR] = ServiceLifecycle(.paused, reason: "Lock or sleep")
                        case .failed(let reason): self.serviceStates[.screenOCR] = ServiceLifecycle(.failed, reason: reason)
                        default: break
                        }
                        if case .failed(let message) = state {
                            self.enabled.remove(.screenOCR); self.ocrEpoch = UUID(); self.ocrCapture.stop()
                            self.errorMessage = message
                        }
                    }, onEvent: { [weak self] event in
                        guard let self, self.ocrEpoch == epoch, self.enabled.contains(.screenOCR), !self.isStopping, !self.deleteBusy else { return }
                        self.acceptCaptureEvent(event)
                    })
                case .screenpipe: enabled.insert(feature)
                }
            } else {
                switch feature {
                case .mailFinance,.dailyReports,.projectContext,.overnightAgents: try automation.setEnabled(feature,false)
                case .activity: activityEpoch = UUID(); activity?.stop(); activity = nil
                case .keepAwake: try awake?.stop(); awake = nil
                case .screenOCR: ocrEpoch = UUID(); ocrState = .stopping; ocrCapture.stop(); ocrState = .stopped
                case .screenpipe: cancelScreenpipe(); screenpipeResults = []; apiToken = ""
                }
                enabled.remove(feature)
            }
            if (!value || ![NewtonFeature.screenOCR,.mailFinance,.dailyReports,.projectContext,.overnightAgents].contains(feature)) && !(feature == .activity && value && serviceStates[feature]?.phase == .blocked) {
                serviceStates[feature] = ServiceLifecycle(value ? .running : .disabled, reason: value ? "Enabled" : "Disabled", lastSuccessfulActivity: serviceStates[feature]?.lastSuccessfulActivity)
            }
            automation.recordCoverage(source: feature.rawValue,state: serviceStates[feature]?.phase.rawValue ?? "unknown",reason: serviceStates[feature]?.reason ?? "Unknown")
            status = "\(feature.title) \(enabled.contains(feature) ? "enabled" : "disabled")"
        } catch { serviceStates[feature] = ServiceLifecycle(.failed, reason: error.localizedDescription); report(error) }
    }

    private func acceptCaptureEvent(_ event: HistoryEvent) {
        if event.source == "Activity" { serviceStates[.activity] = ServiceLifecycle(.running, reason: "App activation observed", lastSuccessfulActivity: event.timestamp) }
        pendingEvents.append(event); pendingWriteCount = pendingEvents.count
        if pendingEvents.count >= 4096 {
            applyFeature(.activity, enabled: false); applyFeature(.screenOCR, enabled: false)
            status = "Capture paused at the pending-write limit · accepted events will be saved"
        }
        startIngesting()
    }
    private func startIngesting() {
        guard ingestTask == nil, let store, !pendingEvents.isEmpty else { return }
        ingestTask = Task { [weak self] in
            guard let self else { return }
            var failed = false
            while !self.pendingEvents.isEmpty {
                let batch = Array(self.pendingEvents.prefix(128))
                do {
                    try await store.append(batch)
                    self.historyWritten()
                    self.pendingEvents.removeFirst(batch.count)
                    self.pendingWriteCount = self.pendingEvents.count
                } catch {
                    failed = true; self.writeFailed = true
                    self.applyFeature(.activity, enabled: false); self.applyFeature(.screenOCR, enabled: false)
                    self.report(error)
                    self.status = "Capture stopped · \(self.pendingEvents.count) unsaved events retained for retry"
                    break
                }
            }
            self.ingestTask = nil
            if !failed {
                self.writeFailed = false
                if self.historyClients > 0 && self.presentationVisible { await self.refresh() }
                else { await self.refreshCount() }
            }
        }
    }
    public func retryPendingWrites() async {
        guard !deleteBusy, !isStopping else { return }
        startIngesting(); await ingestTask?.value
    }
    public func flushActivity() async { await ingestTask?.value }

    public func setPresentationVisible(_ value: Bool) {
        presentationVisible = value
        if !value { searchTask?.cancel(); invalidateTimeline() }
        else { if historyClients > 0 { scheduleSearch() }; if timelineClients > 0 { requestTimeline() } }
    }
    public func presentHistory() { historyClients += 1; scheduleSearch() }
    public func dismissHistory() { historyClients = max(0, historyClients - 1) }
    public func scheduleSearch() {
        guard ready, !isStopping else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            await self?.refresh()
        }
    }
    public func refresh() async {
        guard let store, !isStopping else { return }
        generation += 1; let request = generation; let requestedQuery = query
        countGeneration += 1; let countRequest = countGeneration
        historyBusy = true
        defer { if request == generation { historyBusy = false } }
        do {
            let page = try await store.page(requestedQuery, after: nil, limit: 100)
            guard request == generation, !Task.isCancelled else { return }
            events = page.events; nextCursor = page.nextCursor; hasMoreHistory = page.nextCursor != nil
            if countRequest == countGeneration { totalEvents = page.totalCount }
        } catch { if request == generation, !(error is CancellationError) { report(error) } }
    }
    private func refreshCount() async {
        guard let store else { return }
        countGeneration += 1; let request = countGeneration
        do {
            let count = try await store.count()
            if request == countGeneration { totalEvents = count }
        } catch { report(error) }
    }
    public func loadMore() async {
        guard let store, let cursor = nextCursor, !historyBusy, !loadingMore, !isStopping else { return }
        let request = generation; let requestedQuery = query
        loadingMore = true
        defer { loadingMore = false }
        do {
            let page = try await store.page(requestedQuery, after: cursor, limit: 100)
            guard request == generation, !Task.isCancelled else { return }
            var seen = Set(events.map(\.id))
            events += page.events.filter { seen.insert($0.id).inserted }
            nextCursor = page.nextCursor; hasMoreHistory = page.nextCursor != nil
        } catch { if request == generation, !(error is CancellationError) { report(error) } }
    }

    @discardableResult public func searchScreenpipe() -> Task<Void, Never>? {
        guard enabled.contains(.screenpipe), !screenpipeBusy, !isStopping else { return nil }
        let id = UUID(); remoteID = id
        let requestedQuery = screenpipeQuery, token = apiToken, connector = connector
        screenpipeBusy = true; screenpipeResults = []
        let task = Task { [weak self] in
            defer {
                if self?.remoteID == id { self?.screenpipeBusy = false; self?.remoteTask = nil; self?.remoteID = nil }
            }
            do {
                let result = try await connector.search(requestedQuery, token: token)
                guard !Task.isCancelled, let self, self.remoteID == id, self.enabled.contains(.screenpipe), !self.isStopping else { return }
                self.screenpipeResults = result.events
                self.status = "Screenpipe: \(result.events.count) results · \(result.omitted) unsupported/duplicate rows omitted · memory only"
            } catch {
                if self?.remoteID == id, !Task.isCancelled, !(error is CancellationError) { self?.report(error) }
            }
        }
        remoteTask = task
        return task
    }
    public func cancelScreenpipe() {
        remoteID = nil; remoteTask?.cancel(); remoteTask = nil; screenpipeBusy = false
    }

    public func importLumen() {
        guard ready, !importBusy, !deleteBusy, !isStopping else { return }
        let panel = NSOpenPanel(); let id = UUID()
        importPanel = panel; importID = id; importBusy = true
        panel.title = "Choose a Lumen event JSONL file"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .plainText, .json, .plainText]
        panel.begin { [weak self] response in
            guard let self, self.importID == id else { return }
            self.importPanel = nil; self.importID = nil; self.importBusy = false
            if response == .OK, let url = panel.url, !self.isStopping { self.importFile(url) }
        }
    }
    @discardableResult public func importFile(_ url: URL) -> Task<Bool, Never>? {
        let loader = importLoader
        return coordinateImport {
            let batch = try await loader(url)
            var report = IntakeReport(); report.events = batch.events
            if batch.skipped > 0 { report.diagnostics = ["\(batch.skipped) invalid records skipped"] }
            return FileIntakeResult(report: report)
        }
    }
    /// Sole admission/commit boundary for Lumen, idea and Time Atlas imports.
    @discardableResult private func coordinateImport(idea: (String, String)? = nil,
        loader: @escaping @Sendable () async throws -> FileIntakeResult) -> Task<Bool, Never>? {
        guard let store, ready, !importBusy, !deleteBusy, !isStopping, !workflowExportBusy else { return nil }
        let id = UUID(); importID = id; importBusy = true
        let task = Task { [weak self] in
            defer { if self?.importID == id { self?.importBusy = false; self?.importWriting = false; self?.importTask = nil; self?.importID = nil } }
            do {
                let result = try await loader()
                guard let self, self.importID == id else { return false }
                if let saved = result.savedURL {
                    self.lastIdeaDestination = saved.path
                    if let idea { self.ideaRetry = (idea.0, idea.1, saved) }
                }
                try Task.checkCancellation()
                guard !self.isStopping else { return false }
                self.importWriting = true
                let added = try await store.append(result.report.events)
                self.historyWritten()
                guard self.importID == id, !self.isStopping else { return false }
                let destination = result.savedURL.map { "File saved at \($0.path) · " } ?? ""
                let diagnostics = result.report.diagnostics
                self.status = destination + "Indexed \(added) · \(result.report.events.count - added) existing" +
                    (diagnostics.isEmpty ? "" : " · incomplete intake: " + diagnostics.joined(separator: "; "))
                if !diagnostics.isEmpty { self.errorMessage = diagnostics.joined(separator: "\n") }
                if diagnostics.isEmpty, idea != nil { self.ideaRetry = nil }
                await self.refresh()
                return diagnostics.isEmpty
            } catch {
                if let self, self.importID == id {
                    let saved = self.lastIdeaDestination.map { "File retained at \($0) · " } ?? ""
                    if error is CancellationError { self.status = saved + "Import stopped · completed commits preserved" }
                    else { self.status = saved + "Import/indexing failed · retry with draft retained"; self.report(error) }
                }
                return false
            }
        }
        importTask = task
        return task
    }
    public func cancelImport() {
        if let panel = importPanel {
            importID = nil; importPanel = nil; importBusy = false; panel.cancel(nil)
        }
        if importWriting { status = "Finishing accepted database write · no subsequent intake will start" }
        else { importTask?.cancel() }
    }
    public func refreshQuota() {
        guard !isStopping else { return }
        quotaTask?.cancel(); quotaID = UUID(); let id = quotaID; let loader = quotaLoader
        quotaTask = Task { [weak self] in
            let snapshot = await loader()
            guard let self, self.quotaID == id, !self.isStopping, !Task.isCancelled else { return }
            self.codexQuota = snapshot.quota; self.quotaDiagnostic = snapshot.diagnostic
        }
    }
    public func refreshProjectAtlas() {
        guard !isStopping else { return }
        projectTask?.cancel(); projectID = UUID(); let id = projectID; let loader = projectLoader
        projectTask = Task { [weak self] in
            let projects = await loader()
            guard let self, self.projectID == id, !self.isStopping, !Task.isCancelled else { return }
            if self.trackedProjects != projects {
                self.trackedProjects = projects
                self.historyWritten()
            }
        }
    }

    public func startWorkflowRecording(title: String = "Desktop Workflow") {
        guard ready, !opening, !isStopping, !deleteBusy, !isRecordingWorkflow, pendingWorkflow == nil, !workflowExportBusy else { return }
        recordingID = UUID(); let id = recordingID
        do {
            try workflowRecorder.start(sessionTitle: title) { [weak self] session in
                guard let self, self.recordingID == id, !self.isStopping else { return }
                self.isRecordingWorkflow = false; self.pendingWorkflow = session
                self.status = "Workflow capture stopped at 10,000 actions or 60 minutes · export or discard session"
            }
            isRecordingWorkflow = workflowRecorder.isRecording
            if isRecordingWorkflow { status = "Recording desktop workflow actions…" }
        } catch { isRecordingWorkflow = false; report(error) }
    }
    public func discardWorkflow() {
        guard !workflowExportBusy else { return }
        pendingWorkflow = nil; workflowBundle = nil
        status = "Workflow session discarded; any already saved bundle is preserved"
    }
    @discardableResult
    public func stopWorkflowRecording() async -> String? {
        guard !isStopping, !deleteBusy, !workflowExportBusy else { return nil }
        recordingID = UUID()
        if isRecordingWorkflow { pendingWorkflow = workflowRecorder.stop(); isRecordingWorkflow = false }
        guard let session = pendingWorkflow, let store else { return nil }
        workflowExportBusy = true
        let exporter = workflowExporter, location = directory.appendingPathComponent("Workflows")
        let task = Task { () -> String? in
            defer { self.workflowExportBusy = false; self.workflowExportTask = nil }
            do {
                let bundle: URL
                if let existing = self.workflowBundle { bundle = existing }
                else { bundle = try await exporter(session, location); self.workflowBundle = bundle }
                self.status = "Workflow files saved at \(bundle.path) · indexing…"
                let event = HistoryEvent(id: "workflow:" + session.id, timestamp: session.startedAt,
                                         source: "Workflow Synthesizer", title: session.title,
                                         detail: "Experimental replay bundle: \(bundle.path)")
                do { try await store.append([event]); self.historyWritten() }
                catch {
                    self.status = "Workflow files saved at \(bundle.path); indexing failed · retry or discard"
                    self.report(error); return nil
                }
                self.pendingWorkflow = nil; self.workflowBundle = nil
                self.status = "Workflow files saved and indexed: \(bundle.path) · replay experimental"
                if !self.isStopping { await self.refresh() }
                return bundle.appendingPathComponent("replay.py").path
            } catch {
                self.status = "Workflow export failed · session retained for retry or discard"; self.report(error); return nil
            }
        }
        workflowExportTask = task
        return await task.value
    }

    public func dispatchIdeaToCodex(title: String, detail: String = "", provider: AIModelProvider = .codex) async {
        guard ready, !isStopping, !deleteBusy, agentID == nil,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !agentRepositoryPath.isEmpty else { errorMessage = "Select a local Git repository path before running an agent."; return }
        let root = URL(fileURLWithPath: agentRepositoryPath), id = UUID(), runner = manualAgent
        agentID = id; agentCancelling = false
        activeAgentStatus = AgentTaskStatus(taskTitle: title, runID: id, phase: .preparing)
        status = "Preparing manual agent · quota advisory: \(quotaDescription)"
        let operation = Task { [weak self] in
            await runner.run(id: id, task: PromptTask(title: title, objective: detail.isEmpty ? title : detail), repository: root, provider: provider, unattended: false) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.agentID == progress.runID, !self.isStopping, !self.agentCancelling,
                          self.activeAgentStatus?.isRunning == true else { return }
                    self.pendingAgentProgress = progress
                    self.scheduleAgentProgress()
                }
            }
        }
        agentTask = operation
        let result = await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
        guard agentID == id else { return }
        clearAgentProgress(); agentID = nil; agentTask = nil; activeAgentStatus = result
        if !isStopping { status = "Manual agent \(result.phase.rawValue) · worktree/base shown below; no merge or push performed" }
    }
    private func scheduleAgentProgress() {
        guard agentProgressTask == nil else { return }
        agentProgressTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self else { return }
            defer { self.agentProgressTask = nil; self.pendingAgentProgress = nil }
            guard let progress = self.pendingAgentProgress, self.agentID == progress.runID,
                  !self.isStopping, !self.agentCancelling, self.activeAgentStatus?.isRunning == true else { return }
            self.activeAgentStatus = progress
        }
    }
    private func clearAgentProgress() {
        agentProgressTask?.cancel(); agentProgressTask = nil; pendingAgentProgress = nil
    }
    public func cancelAgent() {
        guard let id = agentID else { return }
        clearAgentProgress(); agentCancelling = true; agentTask?.cancel()
        let runner = manualAgent
        Task { await runner.cancel(id: id) }
    }
    public func importICloudIdeas() async {
        let loader = fileIntake, directory = ideasDirectory()
        _ = await coordinateImport { try await loader(.ideas(directory)) }?.value
    }
    public func importTimeAtlas() async {
        let loader = fileIntake, directory = atlasDirectory()
        _ = await coordinateImport { try await loader(.timeAtlas(directory)) }?.value
    }
    @discardableResult public func saveQuickIdea(title: String, detail: String = "") async -> Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let loader = fileIntake, directory = ideasDirectory()
        let existing = ideaRetry.flatMap { $0.title == title && $0.detail == detail ? $0.url : nil }
        let task = coordinateImport(idea: (title, detail)) {
            try await loader(.saveIdea(title: title, detail: detail, directory: directory, existing: existing))
        }
        return await task?.value ?? false
    }

    public func deleteHistory() async {
        guard let store, !importBusy, !deleteBusy, !isStopping, !workflowExportBusy, !isRecordingWorkflow, agentID == nil else { return }
        pauseAll()
        do { try await automation.stop() } catch { report(error); return }
        invalidateTimeline(); clearTimeline()
        deleteBusy = true
        defer { deleteBusy = false }
        applyFeature(.activity, enabled: false); applyFeature(.screenOCR, enabled: false)
        await ingestTask?.value
        do {
            try await store.deleteAll()
            pendingEvents = []; pendingWriteCount = 0; writeFailed = false
            await refresh()
            requestTimeline()
            status = "History removed from search. Database pages and backups may retain traces."
        } catch { report(error) }
    }
    public func revealStorage() { NSWorkspace.shared.open(directory) }

    public func shutdown() async throws {
        if let shutdownTask { try await shutdownTask.value; return }
        let task = Task { try await self.finishShutdown() }
        shutdownTask = task
        do { try await task.value } catch { shutdownTask = nil; isStopping = false; throw error }
    }
    private func finishShutdown() async throws {
        guard !deleteBusy else { throw StoreError(message: "Wait for history deletion to finish before quitting.") }
        isStopping = true
        setFocusShield(false); automation.setSuspended(true)
        speech.stopLiveMeeting(); keyboard.stop()
        for feature in NewtonFeature.allCases { applyFeature(feature,enabled: false) }
        await systemSpeech.stop()
        try await automation.stop()
        // Release capture before waiting on cleanup or child-process teardown.
        for feature in NewtonFeature.allCases { applyFeature(feature, enabled: false) }
        cleanupTask?.cancel(); await cleanupTask?.value
        invalidateTimeline(); clearTimeline()
        quotaTask?.cancel(); projectTask?.cancel(); quotaID = UUID(); projectID = UUID()
        if let id = agentID {
            clearAgentProgress(); agentCancelling = true; agentTask?.cancel(); await manualAgent.cancel(id: id)
            if let final = await agentTask?.value, agentID == id { activeAgentStatus = final }
            agentID = nil; agentTask = nil
        }
        recordingID = UUID()
        if let session = workflowRecorder.stop() { pendingWorkflow = session }
        isRecordingWorkflow = false
        _ = await workflowExportTask?.value
        for feature in NewtonFeature.allCases { applyFeature(feature, enabled: false) }
        cancelImport(); searchTask?.cancel(); generation += 1
        // A cancelled file read may be blocked in a cloud provider. It cannot commit after
        // returning because importFile checks cancellation before append; only drain active writes.
        if importWriting { _ = await importTask?.value }
        await ingestTask?.value
        if pendingWorkflow != nil {
            isStopping = false
            throw StoreError(message: "Workflow session retained. Export or explicitly discard it before quitting.")
        }
        guard pendingEvents.isEmpty, !enabled.contains(.keepAwake) else {
            isStopping = false
            throw StoreError(message: "Newton could not save all pending activity or release keep awake. Retry pending writes before quitting.")
        }
    }
    @discardableResult public func scanCleanup(roots: [String]? = nil) -> Task<Void, Never>? {
        guard !cleanupBusy, !isStopping else { return nil }
        cleanupBusy = true; cleanupDiagnostic = nil; cleanupScan = CleanupScan(); cleanupOutcomes = []
        let service = cleanupService
        let task = Task { [weak self] in
            defer { self?.cleanupBusy = false; self?.cleanupTask = nil }
            do {
                let result = try await service.scan(roots: roots)
                guard !Task.isCancelled, let self, !self.isStopping else { return }
                self.cleanupScan = result
            } catch is CancellationError { self?.cleanupDiagnostic = "Scan cancelled; rescan before selecting directories" }
            catch { self?.cleanupDiagnostic = error.localizedDescription }
        }
        cleanupTask = task; return task
    }
    @discardableResult public func trimCleanup(_ candidates: [DeveloperProjectCandidate]) -> Task<Void, Never>? {
        guard !cleanupBusy, !isStopping, !candidates.isEmpty else { return nil }
        cleanupBusy = true; cleanupDiagnostic = nil; cleanupOutcomes = []
        let service = cleanupService
        let task = Task { [weak self] in
            defer { self?.cleanupBusy = false; self?.cleanupTask = nil }
            let results = await service.trim(candidates)
            guard let self else { return }
            self.cleanupOutcomes = results
            let attempted = Set(results.filter { $0.status != .cancelled }.map(\.id))
            self.cleanupScan = CleanupScan(candidates: self.cleanupScan.candidates.filter { !attempted.contains($0.id) },
                diagnostics: self.cleanupScan.diagnostics, isComplete: self.cleanupScan.isComplete)
        }
        cleanupTask = task; return task
    }
    public func cancelCleanup() { cleanupTask?.cancel() }

    @discardableResult public func runMasterTurboSweep() -> Task<Void, Never>? {
        scanCleanup()
    }

    /// Reads the requested range from SQLite rather than the presentation's first history page.
    /// Bounded export/report snapshots disclose truncation and unknown capture gaps.
    public func observations(from start: Date, to end: Date, query: String = "", limit: Int = 50_000) async throws -> DailyHistoryResult {
        guard let store, ready, !deleteBusy, !isStopping else { throw StoreError(message: "Local history unavailable") }
        var records: [HistoryEvent] = [], cursor: RangeHistoryCursor?
        let maximum = max(1, min(limit, 50_000))
        repeat {
            try Task.checkCancellation()
            let page = try await store.rangePage(from: start, to: end, query: query, after: cursor, limit: min(500, maximum - records.count))
            records += page.events; cursor = page.nextCursor
        } while cursor != nil && records.count < maximum
        return DailyHistoryResult(events: records, isComplete: cursor == nil)
    }

    private func invalidateTimeline() {
        timelineGeneration = UUID(); timelineTask?.cancel(); timelineTask = nil
        timelineRefreshTask?.cancel(); timelineRefreshTask = nil; timelineBusy = false
    }
    /// Coalesce accepted writes without delaying explicit date changes.
    private func historyWritten() {
        automation.historyChanged()
        guard presentationVisible,timelineClients > 0, !isStopping, !deleteBusy, timelineRefreshTask == nil else { return }
        let delay = max(0, 1 - Date().timeIntervalSince(lastTimelineRequest))
        timelineRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.timelineRefreshTask = nil; self.requestTimeline()
        }
    }
    public func presentTimeline() { timelineClients += 1; requestTimeline() }
    public func dismissTimeline() { timelineClients = max(0, timelineClients - 1); if timelineClients == 0 { invalidateTimeline() } }
    public func requestTimeline() {
        invalidateTimeline()
        guard let store, ready, !isStopping, !deleteBusy else { return }
        let id = timelineGeneration, date = timelineDate, projects = trackedProjects
        let calendar = Calendar.current
        guard let day = calendar.dateInterval(of: .day, for: date) else { return }
        timelineBusy = true; timelineError = nil; lastTimelineRequest = Date()
        timelineTask = Task { [weak self] in
            defer { if self?.timelineGeneration == id { self?.timelineBusy = false } }
            do {
                let result = try await store.dayEvents(from: day.start, to: day.end, limit: 50_000)
                try Task.checkCancellation()
                // CPU work is independent of UI actor and slider changes.
                let worker = Task.detached(priority: .utility) {
                    let frames = TimeMachineEngine.buildTimeline(events: result.events, trackedProjects: projects, calendar: calendar, targetDate: date)
                    return (frames, TimeMachineEngine.summarize(timeline: frames))
                }
                let (frames, summary) = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard let self, self.timelineGeneration == id, !Task.isCancelled, !self.isStopping, !self.deleteBusy else { return }
                self.timeline = frames; self.timelineSummary = summary; self.timelineComplete = result.isComplete
            } catch {
                if self?.timelineGeneration == id, !Task.isCancelled { self?.timelineError = error.localizedDescription }
            }
        }
    }
    public func waitForTimeline() async {
        while !isStopping {
            let id = timelineGeneration
            await timelineTask?.value
            if id == timelineGeneration { return }
        }
    }
    private func clearTimeline() {
        timeline = []; timelineSummary = TimeMachineEngine.summarize(timeline: [])
        timelineComplete = true
    }

    private func report(_ error: any Error) { errorMessage = error.localizedDescription }
}
