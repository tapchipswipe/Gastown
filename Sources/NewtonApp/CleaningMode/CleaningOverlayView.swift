// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import AppKit
import SwiftUI
import NewtonCore
import NewtonWorkspace

@MainActor
public final class CleaningModeController: ObservableObject {
    public static let shared = CleaningModeController()

    @Published public private(set) var isActive = false
    @Published public private(set) var unlockProgress = 0
    private var panels: [NSPanel] = []
    private weak var service: KeyboardProtectionService?
    public func configure(with model: WorkspaceModel) {
        service = model.keyboard
        model.keyboard.onCleaningChanged = { [weak self] active in
            guard let self else { return }
            if active { self.showOverlay() } else { self.dismissOverlay() }
        }
        model.keyboard.onUnlockProgress = { [weak self] in self?.unlockProgress = $0 }
        model.keyboard.onHoldChanged = { name, shortcut, progress in
            guard let name else { QuitProtectionHUD.shared.dismiss(); return }
            if progress == 0 { QuitProtectionHUD.shared.show(appName: name, shortcut: shortcut) }
            QuitProtectionHUD.shared.updateProgress(progress, appName: name, shortcut: shortcut)
        }
    }
    private init() {}
    public func toggle() { if isActive { exitCleaningMode() } else { enterCleaningMode() } }
    public func enterCleaningMode() {
        guard let service, !isActive else { return }
        guard service.startCleaning() else {
            let alert = NSAlert(); alert.messageText = "Keyboard cleaning unavailable"
            alert.informativeText = service.state.reason; alert.runModal(); return
        }
    }
    private func showOverlay() {
        guard !isActive else { return }
        isActive = true; unlockProgress = 0
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: CleaningOverlayView(controller: self, keepScreenVisible: CleaningModeEngine.shared.keepScreenVisible))
            panel.setFrame(screen.frame, display: true); panel.orderFrontRegardless(); panels.append(panel)
        }
    }
    public func exitCleaningMode() { service?.stopCleaning(); dismissOverlay() }
    private func dismissOverlay() {
        isActive = false; unlockProgress = 0
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
    }
}

public struct CleaningOverlayView: View {
    @ObservedObject var controller: CleaningModeController
    public let keepScreenVisible: Bool

    public var body: some View {
        ZStack {
            if keepScreenVisible {
                Color.black.opacity(0.4).ignoresSafeArea()
                compactCornerCard
            } else {
                Color.black.ignoresSafeArea()
                fullBlackoutCard
            }
        }
    }

    private var fullBlackoutCard: some View {
        VStack(spacing: 24) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 8) {
                Text("Keyboard Locked for Cleaning")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Safely wipe your keyboard, trackpad, and screen.\nKeypresses are swallowed.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }

            // Unlock Progress Dots
            HStack(spacing: 8) {
                ForEach(0..<CleaningModeEngine.shared.unlockThreshold, id: \.self) { idx in
                    Circle()
                        .fill(idx < controller.unlockProgress ? Color.green : Color.white.opacity(0.2))
                        .frame(width: 10, height: 10)
                        .scaleEffect(idx < controller.unlockProgress ? 1.2 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: controller.unlockProgress)
                }
            }
            .padding(.top, 8)

            Text("Press Escape 5 times to unlock")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))

            Button(action: {
                controller.exitCleaningMode()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                    Text("Unlock Keyboard")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .overlay {
                            Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                        }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .frame(maxWidth: 420)
        .padding(32)
    }

    private var compactCornerCard: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                HStack(spacing: 16) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cleaning Mode Active")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Press Esc 5 times or click unlock")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Button("Unlock") {
                        controller.exitCleaningMode()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white.opacity(0.2)))
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .padding(24)
            }
        }
    }
}
