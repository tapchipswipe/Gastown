import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

private enum Destination: String, CaseIterable, Identifiable {
    case overview = "Mission Control"
    case timeline = "Visual Timeline & OCR"
    case pipes = "Pipes & SOPs"
    case automation = "Automatic Intelligence"
    case meetings = "Meeting Transcription"
    case ports = "Developer Ports"
    case atlas = "Project & Life Atlas"
    case aiQuota = "AI Quota & Agents"
    case history = "Work History"
    case finance = "Financial Runway"
    case storage = "iCloud & Storage"
    case utilities = "Utilities & Clean"
    case connections = "Connections"
    case privacy = "Privacy & Data"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .timeline: "photo.stack.fill"
        case .pipes: "play.square.stack.fill"
        case .automation: "sparkles"
        case .meetings: "mic"
        case .ports: "network"
        case .atlas: "globe.americas"
        case .aiQuota: "brain.head.profile"
        case .history: "clock.arrow.circlepath"
        case .finance: "banknote.fill"
        case .storage: "icloud.fill"
        case .utilities: "slider.horizontal.3"
        case .connections: "point.3.connected.trianglepath.dotted"
        case .privacy: "hand.raised"
        }
    }
}

public struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    @State private var destination: Destination? = .overview
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $destination) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("Newton")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.enabled.contains(.activity) ? "Activity on" : "Activity off",
                          systemImage: model.enabled.contains(.activity) ? "record.circle" : "pause.circle")
                    Text("Newton · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "v0.1.7")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            Group {
                switch destination ?? .overview {
                case .overview: OverviewView(model: model)
                case .timeline: VisualTimelineView(model: model)
                case .pipes: PipesStudioView(model: model)
                case .automation: AutomaticIntelligenceView(model: model)
                case .meetings: MeetingTranscriptionView(model: model)
                case .ports: PortManagerView(model: model)
                case .atlas: AtlasView(model: model)
                case .aiQuota: AIQuotaView(model: model)
                case .history: HistoryView(model: model)
                case .finance: FinancialRunwayView(model: model)
                case .storage: GhostFileInspectorView(model: model)
                case .utilities: UtilitiesView(model: model)
                case .connections: ConnectionsView(model: model)
                case .privacy: PrivacyView(model: model).padding(28)
                }
            }
            .navigationTitle((destination ?? .overview).rawValue)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    NotchView(model: model)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(model.isPaused ? "Resume Selected" : "Pause All", systemImage: model.isPaused ? "play.fill" : "pause.fill") {
                        if model.isPaused { model.resumeAll() } else { model.pauseAll() }
                    }
                    // Floating Shelf
                    Button {
                        ShelfWindowController.shared.toggle()
                    } label: {
                        Image(systemName: "tray.and.arrow.down.fill")
                    }
                    .help("Toggle Floating Drop Shelf")

                    // ⌘K Palette
                    Button {
                        CommandBarWindowController.shared.configure(with: model)
                        CommandBarWindowController.shared.toggle()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "command")
                            Text("K")
                        }
                    }
                    .help("Toggle ⌘K Command Palette")

                    // Import Lumen
                    Button("Import", systemImage: "square.and.arrow.down", action: model.importLumen)
                        .disabled(!model.ready || model.importBusy || model.deleteBusy || model.isStopping)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    if model.opening || model.importBusy || model.deleteBusy { ProgressView().controlSize(.small) }
                    if !model.ready && !model.opening { Button("Retry Opening") { Task { await model.open() } } }
                    if model.importBusy { Button("Cancel Import", action: model.cancelImport) }
                    if model.writeFailed && model.pendingWriteCount > 0 { Button("Retry \(model.pendingWriteCount) Unsaved Events") { Task { await model.retryPendingWrites() } } }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: model.requestedSection) { _, section in
            if let section { destination = Destination(rawValue: section); model.requestedSection = nil }
        }
        .sheet(isPresented: Binding(get: { model.ready && !model.setupComplete }, set: { _ in })) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up Newton").font(.title.bold())
                Text("Choose capabilities once. Newton saves your selection and resumes it after relaunch. Pause All stops collection. Screen OCR needs Screen Recording; global keyboard tools need Accessibility. Missing permissions are shown as blocked.")
                ForEach(NewtonFeature.allCases.filter { $0 != .screenpipe }) { feature in
                    Toggle(feature.title, isOn: Binding(get: { model.selectedFeatures.contains(feature) }, set: { model.toggle(feature, enabled: $0) }))
                    Text(feature.explanation).font(.caption).foregroundStyle(.secondary)
                if let state = model.serviceStates[feature] { Text(state.phase.rawValue + " · " + state.reason).font(.caption).foregroundStyle(.secondary) }
                }
                Text("Excluded app bundle IDs (one per line)").font(.caption)
                TextEditor(text: $model.captureExcludedApps).frame(height: 60)
                Button("Save Choices", action: model.completeSetup).buttonStyle(.borderedProminent)
            }.padding(28).frame(width: 520)
        }
        .alert("Newton", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewtonNavigateToPorts"))) { _ in
            destination = .ports
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewtonNavigateToStorage"))) { _ in
            destination = .storage
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewtonRunStandupPipe"))) { _ in
            destination = .pipes
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NewtonRunMissedTodosPipe"))) { _ in
            destination = .pipes
        }
        .onAppear {
            CommandBarWindowController.shared.configure(with: model)
            NotchWindowController.shared.configure(with: model)
            DesktopHUDWindowController.shared.configure(with: model)

            if let section = model.requestedSection { destination = Destination(rawValue: section); model.requestedSection = nil }
        }
    }
}

private struct OverviewView: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little gravity for your work.").font(.largeTitle.bold())
                    Text("Independent local work history, daily utilities and source-grounded automatic intelligence.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    MetricCard(title: "Context Events", value: "\(model.totalEvents)", caption: "Total recorded history", symbol: "sparkles")
                    MetricCard(title: "Active Features", value: "\(model.enabled.count) of \(NewtonFeature.allCases.count)", caption: "Selected local capabilities", symbol: "bolt.fill")
                    MetricCard(title: "Tracked Repos", value: "\(model.trackedProjects.count)", caption: "Auto-detected git roots", symbol: "folder.fill")
                    MetricCard(title: "Tracked Days", value: "\(model.timelineSummary.observedIntervals > 0 ? "Active" : "Ready")", caption: "\(model.timelineSummary.observedIntervals) observed 5m frames", symbol: "calendar")
                }
                QuotaFreshnessLabel(model: model).font(.caption).foregroundStyle(.secondary)
                if let quota = model.codexQuota {
                    HStack(spacing: 16) {
                        Image(systemName: "brain.head.profile").font(.largeTitle).foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("AI Quota: \(Int(quota.primary.remainingPercent))% available")
                                    .font(.headline)
                                Text("· \(model.scheduleMode == .daytimeUserReserve ? "Daytime User Reserve" : "Nighttime advisory")")
                                    .font(.caption).foregroundStyle(model.scheduleMode == .daytimeUserReserve ? .green : .purple)
                            }
                            Text("5h rolling window resets at \(quota.primary.resetsAt.formatted(date: .omitted, time: .shortened)) · Plan: \(quota.planType.uppercased())")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh", action: model.refreshQuota).buttonStyle(.bordered).controlSize(.small)
                    }
                    .panelCard(cornerRadius: 14)
                }
                TimeMachineScrubberView(model: model)
                Text("Build your orbit").font(.title2.bold())
                Text("Every feature starts off. Turn on only what you need.").foregroundStyle(.secondary)
                ForEach(NewtonFeature.allCases) { feature in FeatureRow(feature: feature, model: model) }
                Text("Screen OCR: " + model.ocrState.description).font(.caption)
                VStack(alignment: .leading, spacing: 10) {
                    Label("Newton Super-App Orbit", systemImage: "sparkles").font(.headline)
                    Text("Standalone desktop tools, local OCR and evidence reports.")
                    Text("Available: Dynamic Notch Island, ⌘K Command Palette, Floating Drop Shelf, Desktop Glass HUD, and Standup Pipes.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelCard(cornerRadius: 14)
            }.padding(28)
        }
    }
}

private struct MetricCard: View {
    let title: String; let value: String; let caption: String; let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption.bold()).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelCard(cornerRadius: 14)
    }
}

private struct FeatureRow: View {
    let feature: NewtonFeature
    @Bindable var model: WorkspaceModel
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: feature.symbol).font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title).font(.headline)
                Text(feature.explanation).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(feature.title, isOn: Binding(get: { model.enabled.contains(feature) },
                                                set: { model.toggle(feature, enabled: $0) }))
                .labelsHidden().toggleStyle(.switch).disabled(!model.ready || model.deleteBusy || model.isStopping)
        }
        .panelCard(cornerRadius: 14)
    }
}

private struct HistoryView: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        VStack(spacing: 0) {
            TimeMachineScrubberView(model: model)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search local history", text: $model.query)
                    .textFieldStyle(.plain)
                if !model.query.isEmpty { Button("Clear") { model.query = "" } }
            }.padding(16)
            Text("Showing \(model.events.count) of \(model.totalEvents) stored events · search matches may be fewer")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            Divider()
            if model.events.isEmpty {
                ContentUnavailableView(model.query.isEmpty ? "Your story starts here" : "No matching events",
                                       systemImage: "clock", description: Text("Enable Activity history or import a Lumen JSONL file."))
            } else {
                List {
                    ForEach(model.events) { event in EventRow(event: event) }
                    if model.hasMoreHistory {
                        Button(model.loadingMore ? "Loading…" : "Load more history") { Task { await model.loadMore() } }
                            .disabled(model.loadingMore || model.historyBusy)
                    }
                }
            }
        }
        .onAppear { model.presentHistory() }
        .onDisappear { model.dismissHistory() }
    }
}

private struct EventRow: View {
    let event: HistoryEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(event.title).font(.headline)
                Spacer()
                Text(event.timestamp, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            }
            if !event.detail.isEmpty { Text(event.detail).font(.callout).lineLimit(4).textSelection(.enabled) }
            Text(event.source).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 7)
    }
}

private struct UtilitiesView: View {
    @Bindable var model: WorkspaceModel
    @State private var cleanupSelection: [DeveloperProjectCandidate] = []
    @State private var powerSnapshot = PowerPacingEngine.captureSnapshot()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("System Engines & Utilities").font(.largeTitle.bold())
                    Text("Available battery information, developer cleanup, and desktop controls.").font(.title3).foregroundStyle(.secondary)
                }

                // Battery & thermal information Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .font(.title2)
                            .foregroundStyle(powerSnapshot.isCharging == true ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery & thermal information").font(.headline)
                            Text(powerSnapshot.narrative).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Refresh") {
                            powerSnapshot = PowerPacingEngine.captureSnapshot()
                        }
                        .controlSize(.small)
                    }

                    Divider()

                    Text(powerSnapshot.batteryPercent.map { "Battery: \($0)%" } ?? "Battery level unavailable").font(.caption)
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery discharge").font(.caption).foregroundStyle(.secondary)
                            Text("Sub-4W")
                                .font(.title3.bold().monospaced())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery Runway").font(.caption).foregroundStyle(.secondary)
                            Text(powerSnapshot.runwayFormatted)
                                .font(.title3.bold())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Thermal State").font(.caption).foregroundStyle(.secondary)
                            Text(powerSnapshot.thermalState)
                                .font(.title3.bold())
                        }
                        if let cycles = powerSnapshot.cycleCount {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cycle Count").font(.caption).foregroundStyle(.secondary)
                                Text("\(cycles)")
                                    .font(.title3.bold().monospaced())
                            }
                        }
                    }
                }
                .panelCard(cornerRadius: 14)

                // Developer cache cleanup
                VStack(alignment: .leading, spacing: 10) {
                    Label("Developer cache cleanup", systemImage: "trash.fill").font(.headline)
                    Text("Scans at most 10,000 entries and sizes at most 100,000 entries per candidate. Directory sizes are estimates, not measured free-space gains.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Scan directories") { model.scanCleanup() }
                            .disabled(model.cleanupBusy || !cleanupSelection.isEmpty)
                        if model.cleanupBusy {
                            ProgressView().controlSize(.small)
                            Button("Cancel cleanup", action: model.cancelCleanup)
                        }
                        Button("Review all directories…") { cleanupSelection = model.cleanupScan.candidates }
                            .disabled(model.cleanupBusy || model.cleanupScan.candidates.isEmpty)
                    }
                    if let diagnostic = model.cleanupDiagnostic { Text(diagnostic).font(.caption) }
                    if !model.cleanupScan.isComplete { Text("Incomplete scan").foregroundStyle(.orange) }
                    ForEach(model.cleanupScan.diagnostics, id: \.self) { Text($0).font(.caption) }
                    ForEach(model.cleanupScan.candidates) { candidate in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(candidate.bloatPath).textSelection(.enabled)
                                Text(candidate.sizeFormatted).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Review…") { cleanupSelection = [candidate] }.disabled(model.cleanupBusy)
                        }
                    }
                    ForEach(model.cleanupOutcomes) { outcome in
                        VStack(alignment: .leading) {
                            Text(outcome.status.rawValue.capitalized + " · " + outcome.candidate.bloatPath).font(.caption.bold())
                            Text(outcome.detail).font(.caption)
                        }
                    }
                }
                .panelCard(cornerRadius: 14)
                .sheet(isPresented: Binding(get: { !cleanupSelection.isEmpty }, set: { if !$0 { cleanupSelection = [] } })) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Delete these cache directories?").font(.headline)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(cleanupSelection) { Text($0.bloatPath).textSelection(.enabled) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Deletion is permanent. Cancellation stops before the next directory; it cannot restore a deletion already underway. Estimated sizes do not guarantee free-space gains.").font(.caption)
                        HStack {
                            Button("Cancel", role: .cancel) { cleanupSelection = [] }
                            Spacer()
                            Button("Delete selected directories", role: .destructive) {
                                model.trimCleanup(cleanupSelection); cleanupSelection = []
                            }.disabled(model.cleanupBusy)
                        }
                    }.padding(24).frame(width: 650, height: 420)
                }

                // Keep Awake
                VStack(alignment: .leading, spacing: 8) {
                    FeatureRow(feature: .keepAwake, model: model)
                    Text("Keep awake uses a macOS power assertion. Disabling it releases the assertion immediately; quitting Newton also releases it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
    }
}

private struct ConnectionsView: View {
    @Bindable var model: WorkspaceModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Bring your context together.").font(.largeTitle.bold())
            FeatureRow(feature: .screenpipe, model: model)
            Text("Embedded Screenpipe Engine: On-device Vision OCR indexing into Newton's local SQLite FTS5 database. Searches run locally; optional external Screenpipe connection supported.")
                .foregroundStyle(.secondary)
            if model.enabled.contains(.screenpipe) {
                SecureField("Optional Screenpipe API token · kept in memory", text: $model.apiToken)
                HStack {
                    TextField("Search Screenpipe history", text: $model.screenpipeQuery)
                    Button(model.screenpipeBusy ? "Searching…" : "Search") { model.searchScreenpipe() }
                        .disabled(model.screenpipeBusy)
                    if model.screenpipeBusy { Button("Cancel", action: model.cancelScreenpipe) }
                }
                Text("Searches Newton's on-device SQLite FTS5 index and optional 127.0.0.1:3030 service.").font(.caption).foregroundStyle(.secondary)
                List(model.screenpipeResults) { event in EventRow(event: event) }
            } else {
                Spacer()
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lumen event files").font(.headline)
                    Text("Read a file you select. Repeat imports skip existing events.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose JSONL…", action: model.importLumen).disabled(!model.ready || model.importBusy || model.deleteBusy || model.isStopping)
            }
            .panelCard(cornerRadius: 14)
        }.padding(28)
    }
}

public struct PrivacyView: View {
    @Bindable var model: WorkspaceModel
    @State private var showDeleteConfirmation = false
    public init(model: WorkspaceModel) {
        self.model = model
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Your context stays yours.", systemImage: "hand.raised.fill").font(.title2.bold())
            Text("Newton records selected sources only. Saved capability choices resume after setup; Pause All persists across relaunch.")
            Text("Local history uses SQLite in Application Support/Newton. It is not encrypted by Newton. Screenpipe controls its own recording, retention, and cloud features.")
                .foregroundStyle(.secondary)
            Text("Excluded app bundle IDs (one per line)").font(.headline)
            TextEditor(text: $model.captureExcludedApps).frame(height: 90)
            Text("Excluded windows are removed from main-display OCR. Secure input blocks supported capture paths; coverage gaps stay visible.").font(.caption)
            Button("Show Newton Data Folder", action: model.revealStorage)
            Divider()
            Text("Remove history").font(.headline)
            Text("Pauses collection and removes observation search history. Receipt evidence, full transcripts, stored reports and code worktrees remain separately stored. This is not secure erasure and does not delete external originals.")
                .foregroundStyle(.secondary)
            Button("Delete Observation History…", role: .destructive) { showDeleteConfirmation = true }.disabled(!model.ready || model.importBusy || model.deleteBusy || model.isStopping)
        }
        .confirmationDialog("Delete observation history?", isPresented: $showDeleteConfirmation) {
            Button("Delete History", role: .destructive) { Task { await model.deleteHistory() } }
        } message: { Text("This cannot be undone. Original Lumen and Screenpipe data is unchanged.") }
    }
}

private struct AIQuotaView: View {
    @Bindable var model: WorkspaceModel
    @State private var selectedProvider: AIModelProvider = .codex
    @State private var manualTitle = ""
    @State private var manualObjective = ""

    private var policyDecision: ExecutionDecision {
        let scheduler = AIScheduler()
        return scheduler.evaluateQuotaPolicy(now: Date(), quota: model.codexQuota)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Quota & Manual Providers").font(.title.bold())
                        Text("Run one provider manually in an isolated checkout. Quota snapshots are advisory.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh Quota", systemImage: "arrow.clockwise", action: model.refreshQuota)
                        .buttonStyle(.bordered)
                }

                QuotaFreshnessLabel(model: model).font(.caption).foregroundStyle(.secondary)

                // Day / Night Policy Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(systemName: model.scheduleMode == .daytimeUserReserve ? "sun.max.fill" : "moon.stars.fill")
                            .font(.title)
                            .foregroundStyle(model.scheduleMode == .daytimeUserReserve ? .orange : .purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.scheduleMode == .daytimeUserReserve ? "Daytime User Reserve (08:00 – 22:00)" : "Nighttime advisory (22:00 – 08:00)")
                                .font(.headline)
                            Text(policyDecision.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .panelCard(cornerRadius: 14)

                if let quota = model.codexQuota {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Primary Window (\(quota.primary.windowMinutes / 60) hours)")
                                .font(.headline)
                            Spacer()
                            Text("\(Int(quota.primary.remainingPercent))% Remaining (\(Int(quota.primary.usedPercent))% Used)")
                                .font(.subheadline.bold())
                        }
                        ProgressView(value: quota.primary.usedPercent, total: 100)
                            .tint(quota.primary.usedPercent > 80 ? .red : (quota.primary.usedPercent > 50 ? .orange : .blue))
                        HStack {
                            Label("Resets at \(quota.primary.resetsAt.formatted(date: .omitted, time: .standard))", systemImage: "clock")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("Plan: \(quota.planType.uppercased())").font(.caption.bold())
                        }
                    }
                    .panelCard(cornerRadius: 14)

                    if let sec = quota.secondary {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("7-Day Allowance").font(.headline)
                                Spacer()
                                Text("\(Int(sec.remainingPercent))% Remaining").font(.subheadline.bold())
                            }
                            ProgressView(value: sec.usedPercent, total: 100)
                        }
                        .panelCard(cornerRadius: 14)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No Active Codex Session Found", systemImage: "info.circle")
                            .font(.headline)
                        Text("Newton reads bounded tails of local Codex logs. Missing or stale snapshots do not establish provider capacity.")
                            .foregroundStyle(.secondary)
                    }
                    .panelCard(cornerRadius: 14)
                }

                // Dual Provider Routing & Dispatcher
                VStack(alignment: .leading, spacing: 14) {
                    Label("Manual providers · experimental", systemImage: "cpu").font(.headline)
                    Picker("AI Provider", selection: $selectedProvider) {
                        ForEach(AIModelProvider.allCases) { provider in
                            Text(provider == .dualOrchestrated ? "Dual · unavailable" : provider.rawValue).tag(provider).disabled(provider == .dualOrchestrated)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Dual orchestration is unavailable. Provider compatibility awaits an explicit live integration session.").font(.caption)
                    Text(selectedProvider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !model.trackedProjects.isEmpty {
                        Picker("Target Project", selection: $model.agentRepositoryPath) {
                            Text("Select a project...").tag("")
                            ForEach(model.trackedProjects) { project in
                                Text("\(project.name) (\(project.activeBranch))").tag(project.path)
                            }
                        }
                    } else {
                        TextField("Local Git Repository Path", text: $model.agentRepositoryPath)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Task Title (e.g. Implement TimeMachine Replay)", text: $manualTitle)
                        .textFieldStyle(.roundedBorder)

                    TextField("Objective & Requirements (Optional)", text: $manualObjective)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Run Agent in Isolated Worktree", systemImage: "bolt.fill") {
                            Task {
                                await model.dispatchIdeaToCodex(title: manualTitle, detail: manualObjective, provider: selectedProvider)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.activeAgentStatus?.isRunning == true || manualTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.agentRepositoryPath.isEmpty)

                        if model.activeAgentStatus?.isRunning == true {
                            Button("Cancel", role: .destructive, action: model.cancelAgent)
                                .buttonStyle(.bordered)
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let status = model.activeAgentStatus {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(status.taskTitle, systemImage: status.isRunning ? "hourglass" : (status.passedTests == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(status.isRunning ? .blue : (status.passedTests == true ? .green : .red))
                                Spacer()
                                Text(status.phase.rawValue.capitalized)
                                    .font(.caption.bold())
                            }
                            if !status.latestOutput.isEmpty {
                                Text(status.latestOutput)
                                    .font(.caption2.monospaced())
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(.primary.opacity(0.05)))
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(0.03)))
                    }
                }
                .panelCard(cornerRadius: 14)
            }.padding(28)
        }
    }
}

private struct AtlasView: View {
    @Bindable var model: WorkspaceModel
    @State private var quickIdeaTitle = ""
    @State private var quickIdeaDetail = ""
    @State private var workflowTitle = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project & Life Atlas").font(.title.bold())
                        Text("Active local codebases, cross-device ideas, and automated desktop workflows.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sync Ideas", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await model.importICloudIdeas() }
                    }.buttonStyle(.bordered)
                    Button("Sync Time Atlas", systemImage: "iphone") {
                        Task { await model.importTimeAtlas() }
                    }.disabled(model.importBusy || model.deleteBusy || !model.ready)
                    if model.importBusy { Button("Cancel Intake", action: model.cancelImport).buttonStyle(.bordered) }
                }

                // Section 1: Active Local Projects
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Active Development Repositories (\(model.trackedProjects.count))", systemImage: "folder.fill")
                            .font(.headline)
                        Spacer()
                        Button("Scan Repos", systemImage: "arrow.clockwise") {
                            model.refreshProjectAtlas()
                        }.buttonStyle(.bordered).controlSize(.small)
                    }

                    if model.trackedProjects.isEmpty {
                        Text("No git repositories detected in primary workspace roots.")
                            .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
                    } else {
                        ForEach(model.trackedProjects) { project in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(project.name).font(.subheadline.bold())
                                        Text(project.activeBranch).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(.quaternary).clipShape(Capsule())
                                        if project.condition == .unavailable { Text("Unavailable").foregroundStyle(.orange) }
                                        if project.isDirty {
                                            Text("modified").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                    Text(project.lastCommitMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(project.lastCommitDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unavailable")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }.padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .panelCard(cornerRadius: 14)

                // Section 2: Screenpipe Video/Action to Workflow Automation
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Workflow capture · experimental replay", systemImage: "play.square.stack.fill")
                                .font(.headline)
                            Text("Records app switches and mouse clicks. Exports an SOP and experimental Python replay.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isRecordingWorkflow {
                            Button("Stop & Export", systemImage: "stop.circle.fill") {
                                Task { await model.stopWorkflowRecording() }
                            }.buttonStyle(.borderedProminent).tint(.red)
                        } else {
                            Button("Start Recording", systemImage: "record.circle") {
                                let title = workflowTitle.isEmpty ? "Desktop Task" : workflowTitle
                                model.startWorkflowRecording(title: title)
                                if model.isRecordingWorkflow { workflowTitle = "" }
                            }.buttonStyle(.borderedProminent)
                            .disabled(!model.ready || model.pendingWorkflow != nil || model.workflowExportBusy)
                        }
                    }
                    if model.pendingWorkflow != nil {
                        HStack {
                            Button("Retry Export") { Task { await model.stopWorkflowRecording() } }
                            Button("Discard Session", role: .destructive) { model.discardWorkflow() }
                        }.disabled(model.workflowExportBusy)
                    }
                    Text("Replay is experimental. Export does not run it; inspect the script before any explicit replay.").font(.caption)
                    if !model.isRecordingWorkflow {
                        TextField("Workflow name (e.g. 'Deploy Dev Server', 'Export Weekly Invoice')...", text: $workflowTitle)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Actively capturing desktop actions… Perform your task now, then click Stop.").font(.caption).foregroundStyle(.red)
                        }.padding(.vertical, 4)
                    }
                }
                .panelCard(cornerRadius: 14)

                // Section 3: Quick Idea Capture & Autonomous AI Agent Builder
                VStack(alignment: .leading, spacing: 10) {
                    Label("Ideas & Manual Agent", systemImage: "lightbulb.fill").font(.headline)
                    TextField("Local Git repository path for manual agent", text: $model.agentRepositoryPath).textFieldStyle(.roundedBorder)
                    Text("Runs use committed HEAD in a dedicated worktree. Uncommitted edits are excluded; review changes manually. No automatic merge or push.").font(.caption).foregroundStyle(.secondary)
                    if let path = model.lastIdeaDestination { Text("Idea file: " + path + " · cloud upload unverified").font(.caption).textSelection(.enabled) }
                    TextField("Idea title (e.g. 'Add dark mode toggle to menu bar')...", text: $quickIdeaTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Technical constraints, objective, or design notes...", text: $quickIdeaDetail)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save Idea File") {
                            let title = quickIdeaTitle; let detail = quickIdeaDetail
                            Task {
                                if await model.saveQuickIdea(title: title, detail: detail), quickIdeaTitle == title, quickIdeaDetail == detail {
                                    quickIdeaTitle = ""; quickIdeaDetail = ""
                                }
                            }
                        }.disabled(quickIdeaTitle.trimmingCharacters(in: .whitespaces).isEmpty || model.importBusy || model.deleteBusy || !model.ready)

                        Spacer()

                        Button("Build with AI (Codex Agent)", systemImage: "sparkles") {
                            let title = quickIdeaTitle; let detail = quickIdeaDetail
                            Task { await model.dispatchIdeaToCodex(title: title, detail: detail) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(quickIdeaTitle.trimmingCharacters(in: .whitespaces).isEmpty || model.activeAgentStatus?.isRunning == true)
                    }
                }
                .panelCard(cornerRadius: 14)

                // Live Agent Console if running or recent
                if let agent = model.activeAgentStatus {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Manual Agent: \(agent.taskTitle)", systemImage: agent.isRunning ? "gearshape.2" : "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(agent.isRunning ? .blue : (agent.passedTests == true ? .green : .orange))
                            Spacer()
                            if agent.isRunning {
                                ProgressView().controlSize(.small)
                                Button("Cancel Run", action: model.cancelAgent)
                            }
                        }
                        Text("State: " + agent.phase.rawValue + (agent.truncated ? " · output tail truncated to 1 MiB" : "")).font(.caption)
                        if let base = agent.baseRevision { Text("Base: " + base).font(.caption).textSelection(.enabled) }
                        if let path = agent.worktreePath { Text("Worktree: " + path + " (unchanged successful worktrees are removed)").font(.caption).textSelection(.enabled) }
                        ScrollView {
                            Text(agent.latestOutput.isEmpty ? "Waiting for agent output..." : agent.latestOutput)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 160)
                    }
                    .panelCard(cornerRadius: 14)
                }

                // Section 4: Idea & Mobile Stream
                VStack(alignment: .leading, spacing: 8) {
                    Label("Manual file intake (Ideas & Time Atlas)", systemImage: "tray.fill").font(.headline)
                    let atlasEvents = model.events.filter { $0.source.contains("Idea") || $0.source.contains("Time Atlas") || $0.source.contains("Workflow") }
                    if atlasEvents.isEmpty {
                        Text("No ideas or Time Atlas events loaded yet. Click Sync above or drop a note in iCloud.")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 8)
                    } else {
                        ForEach(atlasEvents.prefix(15)) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Label(event.title, systemImage: event.source.contains("Idea") ? "lightbulb" : (event.source.contains("Workflow") ? "bolt.fill" : "figure.walk"))
                                        .font(.subheadline.bold())
                                    Spacer()
                                    Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                if !event.detail.isEmpty {
                                    Text(event.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }.padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .panelCard(cornerRadius: 14)
            }.padding(28)
        }
    }
}

// Only refreshes a label; quota files are read solely by the owned optional scan.
@MainActor struct QuotaFreshnessLabel: View {
    let model: WorkspaceModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(QuotaSnapshot(quota: model.codexQuota, diagnostic: model.quotaDiagnostic).description(at: context.date))
        }
    }
}
