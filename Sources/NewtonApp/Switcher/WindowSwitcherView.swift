import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

public struct WindowSwitcherView: View {
    let windows: [SwitchableWindow]
    @Binding var selectedIndex: Int
    var onSelect: (SwitchableWindow) -> Void
    var onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        windows: [SwitchableWindow],
        selectedIndex: Binding<Int>,
        onSelect: @escaping (SwitchableWindow) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.windows = windows
        self._selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Label("Window Switcher", systemImage: "macwindow.on.rectangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(windows.count) open")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            // Horizontal card strip
            if windows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.dashed")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No switchable windows active")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 320, height: 100)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                            windowCard(for: window, isSelected: index == selectedIndex)
                                .onTapGesture {
                                    selectedIndex = index
                                    onSelect(window)
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Keyboard navigation hint footer
            HStack(spacing: 8) {
                Text("⇥ Next  ·  ⇧⇥ Prev  ·  ↩ Select  ·  Esc Cancel")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 420, maxWidth: 680)
        .background(
            ZStack {
                Theme.spaceGradient
                HUDBackdrop(cornerRadius: 16)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 20, x: 0, y: 10)
    }

    private func windowCard(for window: SwitchableWindow, isSelected: Bool) -> some View {
        VStack(spacing: 6) {
            // App Icon
            appIconView(for: window.pid)
                .frame(width: 44, height: 44)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

            // App Name
            Text(window.appName)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(isSelected ? Color.white : Color.primary)

            // Window Title
            Text(window.windowTitle.isEmpty ? window.appName : window.windowTitle)
                .font(.system(size: 9))
                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
        .padding(10)
        .frame(width: 110, height: 115)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.75) : PanelSurface.controlFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1.5)
        )
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isSelected)
    }

    private func appIconView(for pid: pid_t) -> some View {
        if let app = NSRunningApplication(processIdentifier: pid),
           let icon = app.icon {
            return AnyView(Image(nsImage: icon).resizable().scaledToFit())
        }
        return AnyView(Image(systemName: "app.dashed").font(.largeTitle).foregroundStyle(.secondary))
    }
}
