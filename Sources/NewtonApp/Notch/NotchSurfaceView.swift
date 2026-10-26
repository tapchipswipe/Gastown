import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

/// Modern liquid-glass Notch surface with compact island mode, spring physics, quick window snap, and clipboard history.
public struct NotchExpandedSurfaceView: View {
    @Bindable var model: WorkspaceModel
    @Binding var isExpanded: Bool
    @State private var powerSnapshot = PowerPacingEngine.captureSnapshot()
    @State private var colorSampler = ColorSampler.shared
    @State private var micMute = MicMuteController.shared
    @State private var sampledColorHex: String?
    @State private var scratchpadText = (try? String(contentsOfFile: ("~/.newton_scratchpad.md" as NSString).expandingTildeInPath, encoding: .utf8)) ?? ""
    @State private var clipboardHistory: [String] = []
    @State private var activePortsCount = 0
    @State private var selectedTab = 0 // 0 = Dev & Git, 1 = Clipboard & Snap
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel, isExpanded: Binding<Bool>) {
        self.model = model
        self._isExpanded = isExpanded
    }

    public var body: some View {
        ZStack {
            HUDBackdrop(cornerRadius: isExpanded ? 20 : 18)

            if !isExpanded {
                compactIslandView
            } else {
                expandedDrawerView
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: isExpanded ? 20 : 18, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
        .onAppear {
            refreshClipboard()
            refreshPorts()
        }
    }

    // MARK: - Compact Island View
    private var compactIslandView: some View {
        HStack(spacing: 12) {
            // Power
            HStack(spacing: 4) {
                Image(systemName: powerSnapshot.isPluggedIn == true ? "bolt.fill" : "battery.75")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(powerSnapshot.isCharging == true ? .green : .secondary)
                Text(powerSnapshot.batteryPercent.map { "\($0)%" } ?? "Mac")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }

            Divider().frame(height: 12).opacity(0.4)

            // Active Project / Git
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                if let project = model.trackedProjects.first {
                    Text(project.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text(project.activeBranch)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Newton")
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            Divider().frame(height: 12).opacity(0.4)

            // Dev Ports Badge if active
            if activePortsCount > 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.orange).frame(width: 5, height: 5)
                    Text("\(activePortsCount) ports")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Divider().frame(height: 12).opacity(0.4)
            }

            // Equalizer Bars (Music / Flow)
            HStack(spacing: 2) {
                ForEach(0..<4) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: 2.5, height: CGFloat(6 + ((i * 3) % 8)))
                }
            }

            Spacer()

            // Expand Button
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isExpanded = true
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Expand Dynamic Notch Drawer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Expanded Drawer View
    private var expandedDrawerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top Bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "atom")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                    Text("Newton Notch Hub")
                        .font(.system(size: 12, weight: .bold))
                }

                Spacer()

                // Window Snapping Quick Bar
                HStack(spacing: 4) {
                    ForEach(WindowSnapAction.allCases.prefix(4)) { action in
                        Button {
                            model.perform(.snap(action))
                        } label: {
                            Image(systemName: action.iconName)
                                .font(.system(size: 10))
                                .padding(4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("Snap active window to \(action.rawValue)")
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Text(powerSnapshot.runwayFormatted)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.2)

            // 3-Column Grid
            HStack(alignment: .top, spacing: 12) {
                // Column 1: Git & Dev Dwell
                VStack(alignment: .leading, spacing: 6) {
                    Label("Git & Orbit", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    if let project = model.trackedProjects.first {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name).font(.system(size: 12, weight: .bold))
                            Text("Branch: " + project.activeBranch).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            Text(project.lastCommitMessage)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        Text("No active repository tracked").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Column 2: AI Quota & Ports
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("AI & Ports", systemImage: "brain.head.profile")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        if activePortsCount > 0 {
                            Text("\(activePortsCount) listening")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }

                    if let quota = model.codexQuota {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(Int(quota.primary.remainingPercent))% Available")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(quota.primary.remainingPercent > 20 ? Color.green : Color.orange)
                            Text("Resets: \(quota.primary.resetsAt.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            ProgressView(value: quota.primary.remainingPercent, total: 100)
                                .controlSize(.mini)
                        }
                    } else {
                        Text("Advisory snapshot refreshing…").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Column 3: Scratchpad
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Scratchpad", systemImage: "square.and.pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    TextEditor(text: $scratchpadText)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(height: 70)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .onChange(of: scratchpadText) { _, newText in
                            saveScratchpad(newText)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Clipboard History Strip if available
            if !clipboardHistory.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("Recent Clips:")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    ForEach(clipboardHistory.prefix(3), id: \.self) { clip in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(clip, forType: .string)
                        } label: {
                            Text(clip.prefix(20))
                                .font(.system(size: 9, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy: \(clip)")
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            // Bottom Quick Actions Bar
            HStack(spacing: 8) {
                // Color Sampler
                Button {
                    Task {
                        sampledColorHex = await colorSampler.sampleColor()
                    }
                } label: {
                    Label(sampledColorHex ?? "Eyedropper", systemImage: "eyedropper")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Mic Mute
                Button {
                    micMute.toggleMute()
                } label: {
                    Label(micMute.isMuted ? "Unmute Mic" : "Mute Mic", systemImage: micMute.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(micMute.isMuted ? .red : .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Keep Awake
                Button {
                    model.perform(.toggleAwake)
                } label: {
                    Label(model.enabled.contains(.keepAwake) ? "Awake On" : "Awake Off", systemImage: "cup.and.saucer.fill")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Clean Mode
                Button {
                    model.perform(.toggleCleaning)
                } label: {
                    Label(model.keyboard.cleaningActive ? "Unlock" : "Clean", systemImage: "keyboard")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Pin Snippet
                Button {
                    model.perform(.presentation(.pinLatest))
                } label: {
                    Label("Pin", systemImage: "pin.fill")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                // Trigger ⌘K Command Bar
                Button {
                    model.perform(.presentation(.commandBar))
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "command")
                        Text("K Palette")
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
    }

    private func saveScratchpad(_ text: String) {
        let path = ("~/.newton_scratchpad.md" as NSString).expandingTildeInPath
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func refreshClipboard() {
        if let s = NSPasteboard.general.string(forType: .string), !s.isEmpty {
            let clean = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clipboardHistory.contains(clean) {
                clipboardHistory.insert(clean, at: 0)
                if clipboardHistory.count > 10 { clipboardHistory.removeLast() }
            }
        }
    }

    private func refreshPorts() {
        Task {
            activePortsCount = (try? await PortManagerEngine.scanActivePorts().count) ?? 0
        }
    }
}
