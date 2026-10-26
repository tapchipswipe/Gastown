import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

public enum MenuPanelSectionID: String, CaseIterable, Identifiable, Sendable {
    case toggles = "Quick Toggles & Focus Shield"
    case system = "System Monitor & Apple Silicon Power"
    case windows = "Window Management & Snapping"
    case nowPlaying = "Now Playing"
    case timeline = "Newton Visual Timeline & OCR"
    case pipes = "Evidence Reports"
    case finance = "Receipt Coverage"
    case storage = "iCloud Ghost Files & Scan Cleanup"
    case atlas = "Project Atlas & Codex Quota"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .toggles: return "switch.2"
        case .system: return "cpu"
        case .windows: return "macwindow.on.rectangle"
        case .nowPlaying: return "waveform"
        case .timeline: return "photo.stack.fill"
        case .pipes: return "play.square.stack.fill"
        case .finance: return "banknote.fill"
        case .storage: return "cloud.fill"
        case .atlas: return "globe.americas"
        }
    }
}

/// The core Vorssaint-style flyout popover panel for Newton.
/// Hosts all tools, monitoring, vision timelines, pipes, financial runway, and developer utilities in a single fluid popover.
public struct MenuPanelView: View {
    @Bindable var model: WorkspaceModel
    @State private var powerSnapshot = PowerPacingEngine.captureSnapshot()
    @State private var currentTrack: NowPlayingTrack?
    @State private var collapsedSections: Set<MenuPanelSectionID> = []
    @State private var searchQuery = ""
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider().opacity(0.2)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 12) {
                    // Quick Toggles
                    sectionHeader(.toggles)
                    if !collapsedSections.contains(.toggles) {
                        togglesSectionContent
                    }

                    // System & Power Runway
                    sectionHeader(.system)
                    if !collapsedSections.contains(.system) {
                        systemSectionContent
                    }

                    // Window Snapping
                    sectionHeader(.windows)
                    if !collapsedSections.contains(.windows) {
                        windowsSectionContent
                    }

                    // Cognitive Flow & Audio
                    sectionHeader(.nowPlaying)
                    if !collapsedSections.contains(.nowPlaying) {
                        audioSectionContent
                    }

                    // Screenpipe Timeline & OCR
                    sectionHeader(.timeline)
                    if !collapsedSections.contains(.timeline) {
                        timelineSectionContent
                    }

                    // Evidence Reports
                    sectionHeader(.pipes)
                    if !collapsedSections.contains(.pipes) {
                        pipesSectionContent
                    }

                    // Financial Runway & IRS Schedule-C
                    sectionHeader(.finance)
                    if !collapsedSections.contains(.finance) {
                        financeSectionContent
                    }

                    // iCloud Ghost Files & Scan Cleanup
                    sectionHeader(.storage)
                    if !collapsedSections.contains(.storage) {
                        storageSectionContent
                    }

                    // Project Atlas & Codex Quota
                    sectionHeader(.atlas)
                    if !collapsedSections.contains(.atlas) {
                        atlasSectionContent
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 640)

            Divider().opacity(0.2)

            // Footer Bar
            footerBar
        }
        .frame(width: 440)
        .background(
            ZStack {
                Theme.spaceGradient
                HUDBackdrop(cornerRadius: 16)
            }
        )
        .onAppear {
            refreshTelemetry()
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "atom")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("Newton Super-App")
                    .font(.system(size: 13, weight: .bold))
                Text("v0.1.9")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Settings Button
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Open Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Section Header Helper
    private func sectionHeader(_ section: MenuPanelSectionID) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if collapsedSections.contains(section) {
                    collapsedSections.remove(section)
                } else {
                    collapsedSections.insert(section)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text(section.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: collapsedSections.contains(section) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section 1: Quick Toggles
    private var togglesSectionContent: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Keep Awake
                Button {
                    model.perform(.toggleAwake)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: model.enabled.contains(.keepAwake) ? "cup.and.saucer.fill" : "cup.and.saucer")
                            .font(.system(size: 14))
                            .foregroundStyle(model.enabled.contains(.keepAwake) ? Color.orange : .secondary)
                        Text("Keep Awake")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                // Focus Shield
                Button {
                    model.perform(.toggleFocusShield)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: model.focusShieldActive ? "shield.fill" : "shield")
                            .font(.system(size: 14))
                            .foregroundStyle(model.focusShieldActive ? Color.green : .secondary)
                        Text("Focus Shield")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                // Eyedropper
                Button {
                    model.perform(.presentation(.sampleColor))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentColor)
                        Text("Sampler")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                // Mute Mic
                Button {
                    model.perform(.presentation(.muteMicrophone))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: MicMuteController.shared.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(MicMuteController.shared.isMuted ? Color.red : .secondary)
                        Text("Mute Mic")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                // Clean Mode
                Button {
                    model.perform(.toggleCleaning)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: model.keyboard.cleaningActive ? "keyboard.badge.ellipsis" : "keyboard")
                            .font(.system(size: 14))
                            .foregroundStyle(model.keyboard.cleaningActive ? Color.green : .secondary)
                        Text("Clean Mode")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                // Pin Snippet
                Button {
                    model.perform(.presentation(.pinLatest))
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.orange)
                        Text("Pin Snippet")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Section 2: System Monitor & Power Runway
    private var systemSectionContent: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: powerSnapshot.isPluggedIn == true ? "bolt.fill" : "battery.75")
                        .foregroundStyle(powerSnapshot.isCharging == true ? .green : .secondary)
                    Text(powerSnapshot.batteryPercent.map { "\($0)%" } ?? "Mac")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                Spacer()
                Text(powerSnapshot.runwayFormatted)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }

            if let watts = powerSnapshot.estimatedWatts {
                HStack {
                    Text("Battery discharge estimate")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f W", watts))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Section 3: Window Snapping
    private var windowsSectionContent: some View {
        HStack(spacing: 6) {
            ForEach(WindowSnapAction.allCases.prefix(5)) { action in
                Button {
                    model.perform(.snap(action))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: action.iconName)
                            .font(.system(size: 10))
                        Text(action.rawValue.replacingOccurrences(of: " Window", with: ""))
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(PanelSurface.controlFill(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Section 4: Now Playing
    private var audioSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
                    Button(model.isPaused ? "Resume Selected Services" : "Pause All") {
                        if model.isPaused { model.resumeAll() } else { model.pauseAll() }
                    }.buttonStyle(.borderedProminent)

            if let track = currentTrack {
                HStack(spacing: 10) {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.system(size: 11, weight: .bold)).lineLimit(1)
                        Text(track.artist).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(track.source)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Image(systemName: "speaker.wave.1")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("No active music playback detected")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }


        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Section 5: Screenpipe Timeline & OCR
    private var timelineSectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.totalEvents) OCR Moments Indexed")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("Duplicate sampled-frame suppression")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)
            }

            // Compact 24-Hour Attention Scrubber Bars
            if !model.timeline.isEmpty {
                HStack(spacing: 1.5) {
                    ForEach(Array(model.timeline.prefix(96).enumerated()), id: \.element.id) { _, frame in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(frame.hasObservations ? Color.accentColor : Color.white.opacity(0.12))
                            .frame(height: 8)
                    }
                }
            }

            if let firstEvent = model.events.first {
                HStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text(firstEvent.title)
                        .font(.system(size: 10))
                        .lineLimit(1)
                    Spacer()
                    Text(firstEvent.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Section 6: Evidence Reports
    private var pipesSectionContent: some View {
        HStack(spacing: 8) {
            Button {
                model.perform(.report("Daily Engineering Standup"))
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text.fill").font(.system(size: 12)).foregroundStyle(Color.accentColor)
                    Text("Standup").font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                model.perform(.report("Missed To-Dos Radar"))
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "checklist.checked").font(.system(size: 12)).foregroundStyle(Color.orange)
                    Text("Missed To-Dos").font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                model.perform(.report("Daily Engineering Standup"))
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "person.3.sequence.fill").font(.system(size: 12)).foregroundStyle(Color.purple)
                    Text("Meeting Digest").font(.system(size: 9, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Section 7: Financial Runway & Taxes
    private var financeSectionContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt-observed spending")
                    .font(.system(size: 11, weight: .bold))
                Text("No confirmed receipt coverage")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("30-Day Radar")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text("Mail intake unavailable")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Section 8: Storage & Scan Cleanup
    private var storageSectionContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("6-Pillar iCloud Optimizer")
                    .font(.system(size: 11, weight: .bold))
                Text("Dataless ghost file inspection & eviction")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.perform(.scanCleanup)
            } label: {
                Label("Scan Cleanup", systemImage: "bolt.fill")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)
        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Section 9: Project Atlas & Codex Quota
    private var atlasSectionContent: some View {
        VStack(spacing: 6) {
            if let project = model.trackedProjects.first {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(Color.accentColor)
                        Text(project.name).font(.system(size: 11, weight: .bold))
                        Text(project.activeBranch).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(project.lastCommitMessage)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let quota = model.codexQuota {
                HStack {
                    Text("Codex 5h Quota: \(Int(quota.primary.remainingPercent))% remaining")
                        .font(.system(size: 9.5, weight: .medium))
                    Spacer()
                    Text("Resets \(quota.primary.resetsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack {
            // Overlays quick launchers
            Button {
                CommandBarWindowController.shared.configure(with: model)
                model.perform(.presentation(.commandBar))
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "command")
                    Text("K")
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                NotchWindowController.shared.configure(with: model)
                model.perform(.presentation(.notch))
            } label: {
                Label("Notch", systemImage: "macbook.gen2")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                DesktopHUDWindowController.shared.configure(with: model)
                model.perform(.presentation(.hud))
            } label: {
                Label("HUD", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("Quit", role: .destructive) {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func refreshTelemetry() {
        powerSnapshot = PowerPacingEngine.captureSnapshot()
        currentTrack = AudioFlowProfilerEngine.fetchCurrentTrack()
    }
}
