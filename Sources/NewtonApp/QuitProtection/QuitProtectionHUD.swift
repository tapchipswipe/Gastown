// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import AppKit
import SwiftUI
import NewtonCore

@MainActor
public final class QuitProtectionHUD {
    public static let shared = QuitProtectionHUD()

    private var panel: NSPanel?
    private var progressView: QuitHUDContentView?

    private init() {}

    public func show(appName: String, shortcut: QuitProtectionShortcut = .quit, duration: Double = 0.8) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 280, height: 54),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            
            let hosting = NSHostingView(rootView: QuitHUDContentView(appName: appName, shortcut: shortcut, progress: 0.0))
            p.contentView = hosting
            self.panel = p
        }

        if let hosting = panel?.contentView as? NSHostingView<QuitHUDContentView> {
            hosting.rootView = QuitHUDContentView(appName: appName, shortcut: shortcut, progress: 0.0)
        }

        positionPanel()
        panel?.alphaValue = 1.0
        panel?.orderFrontRegardless()
    }

    public func updateProgress(_ progress: Double, appName: String, shortcut: QuitProtectionShortcut = .quit) {
        if let hosting = panel?.contentView as? NSHostingView<QuitHUDContentView> {
            hosting.rootView = QuitHUDContentView(appName: appName, shortcut: shortcut, progress: progress)
        }
    }

    public func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel?.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.panel?.orderOut(nil)
            }
        })
    }

    private func positionPanel() {
        guard let panel = panel,
              let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - 140
        let y = visibleFrame.minY + 36
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

public struct QuitHUDContentView: View {
    public let appName: String
    public let shortcut: QuitProtectionShortcut
    public let progress: Double

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: shortcut == .quit ? "power" : "xmark.circle")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.red.opacity(0.9))

            VStack(alignment: .leading, spacing: 4) {
                Text(shortcut == .quit ? "Hold ⌘Q to Quit" : "Hold ⌘W to Close")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)

                Text(appName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                // Progress Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 3)

                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.red.opacity(0.8), Color.orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                            .frame(width: geo.size.width * CGFloat(progress), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                }
        }
    }
}
