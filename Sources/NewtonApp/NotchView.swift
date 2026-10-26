import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

/// Modern liquid-glass Notch HUD toolbar element and launcher for the floating Notch overlay.
public struct NotchView: View {
    let model: WorkspaceModel
    @State private var powerSnapshot = PowerPacingEngine.captureSnapshot()
    @State private var colorSampler = ColorSampler.shared
    @State private var micMute = MicMuteController.shared
    @State private var sampledColorHex: String?

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Power & Watts Indicator
            HStack(spacing: 5) {
                Image(systemName: powerSnapshot.isPluggedIn == true ? "bolt.fill" : "battery.75")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(powerSnapshot.isCharging == true ? .green : .primary)
                Text(powerSnapshot.batteryPercent.map { "\($0)%" } ?? "Mac")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .help(powerSnapshot.narrative)

            Divider().frame(height: 14)

            // Active Project / Git Branch
            if let activeProject = model.trackedProjects.first {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("\(activeProject.name)")
                        .font(.system(size: 11, weight: .semibold))
                    if !activeProject.activeBranch.isEmpty {
                        Text("(\(activeProject.activeBranch))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .help("\(activeProject.path) — \(activeProject.isDirty ? "Dirty" : "Clean")")
            } else {
                Text("Newton Orbit")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 14)

            // Live AI Foundry Status
            HStack(spacing: 5) {
                let isRunning = model.activeAgentStatus?.isRunning == true
                Circle()
                    .fill(isRunning ? Color.green : Color.blue)
                    .frame(width: 6, height: 6)
                Text(isRunning ? "Agent Running" : "Manual agents")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 14)

            // Quick Tool Buttons
            HStack(spacing: 8) {
                // Notch Floating Overlay Toggle
                Button {
                    NotchWindowController.shared.configure(with: model)
                    NotchWindowController.shared.toggle()
                } label: {
                    Image(systemName: "macbook.gen2")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Toggle Floating Dynamic Notch Island")

                // Command Bar ⌘K Toggle
                Button {
                    CommandBarWindowController.shared.configure(with: model)
                    CommandBarWindowController.shared.toggle()
                } label: {
                    Image(systemName: "command")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Toggle ⌘K Command Palette")

                // Desktop HUD Toggle
                Button {
                    DesktopHUDWindowController.shared.configure(with: model)
                    DesktopHUDWindowController.shared.toggle()
                } label: {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Toggle Floating Desktop Glass HUD")

                // Color Eyedropper
                Button {
                    Task {
                        sampledColorHex = await colorSampler.sampleColor()
                    }
                } label: {
                    Image(systemName: "eyedropper")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help(sampledColorHex != nil ? "Copied: \(sampledColorHex!)" : "Pick screen color")

                // Mic Mute Toggle
                Button {
                    micMute.toggleMute()
                } label: {
                    Image(systemName: micMute.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(micMute.isMuted ? .red : .primary)
                }
                .buttonStyle(.plain)
                .help(micMute.isMuted ? "Microphone Muted" : "Microphone Active")

                // Keep Awake Toggle
                Button {
                    model.toggle(.keepAwake, enabled: !model.enabled.contains(.keepAwake))
                } label: {
                    Image(systemName: model.enabled.contains(.keepAwake) ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .font(.system(size: 11))
                        .foregroundStyle(model.enabled.contains(.keepAwake) ? .orange : .primary)
                }
                .buttonStyle(.plain)
                .help(model.enabled.contains(.keepAwake) ? "Keep Awake is ON" : "Keep Awake is OFF")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        )
    }
}
