import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

public struct DesktopHUDView: View {
    @Bindable var model: WorkspaceModel
    @State private var isHovered = false
    @State private var currentTrack: NowPlayingTrack?
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 10) {
            // ⌘K Trigger Button
            Button {
                CommandBarWindowController.shared.configure(with: model)
                CommandBarWindowController.shared.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.yellow)
                    Text("⌘K")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Open ⌘K Command Palette")

            Divider().frame(height: 14).opacity(0.3)

            // Active Minutes Focus Meter
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                Text("\(model.totalEvents) observations")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .help("Saved local observations; coverage depends on enabled sources")

            Divider().frame(height: 14).opacity(0.3)

            // Keystrokes Cadence Meter
            HStack(spacing: 4) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentColor)
                Text(model.ocrState.description)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .help("Main-display OCR capture state")

            Divider().frame(height: 14).opacity(0.3)

            // Active Project / Branch
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(model.trackedProjects.first.map { "Recent: " + $0.name } ?? "Active project unknown")
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }

            if let track = currentTrack {
                Divider().frame(height: 14).opacity(0.3)
                HStack(spacing: 4) {
                    Image(systemName: "music.note")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentColor)
                    Text(track.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .help("Now Playing: \(track.title) · \(track.artist)")
            }

            Spacer()

            // Focus Shield 1-Click Toggle
            Button {
                model.perform(.toggleFocusShield)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.focusShieldActive ? "shield.fill" : "shield")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(model.focusShieldActive ? Color.green : Color.secondary)
                    if isHovered || model.focusShieldActive {
                        Text(model.focusShieldActive ? "Shielded" : "Shield")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(model.focusShieldActive ? Color.green : Color.primary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(model.focusShieldActive ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .help("Focus Shield: Dim displays; pointer input remains available")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ZStack {
                HUDBackdrop(cornerRadius: 22)
            }
        )
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 5)
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = inside
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .utility).async {
                let t = AudioFlowProfilerEngine.fetchCurrentTrack()
                DispatchQueue.main.async {
                    self.currentTrack = t
                }
            }
        }
    }
}
