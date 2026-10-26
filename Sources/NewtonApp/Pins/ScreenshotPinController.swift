// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import AppKit
import SwiftUI
import NewtonCore

@MainActor
public final class ScreenshotPinController: ObservableObject {
    public static let shared = ScreenshotPinController()

    @Published public private(set) var activePinCount: Int = 0
    private var windows: [UUID: NSPanel] = [:]

    private init() {}

    public func pinMoment(title: String, text: String, image: NSImage? = nil) {
        let size = ScreenshotPinEngine.calculateAspectRatioFit(
            width: image?.size.width ?? 340,
            height: image?.size.height ?? 220,
            maxDimension: 460
        )

        let pinItem = ScreenshotPinEngine.shared.addPin(
            title: title,
            width: size.width,
            height: size.height
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: size.width, height: size.height + 40),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        // Position on active screen with cascade
        if let screen = NSScreen.main {
            let offset = CGFloat((windows.count % 5) * 30)
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2 + offset,
                y: frame.midY - size.height / 2 - offset
            ))
        }

        let view = PinnedMomentView(
            item: pinItem,
            text: text,
            image: image,
            onClose: { [weak self] in
                self?.closePin(id: pinItem.id)
            },
            onOpacityChange: { [weak panel] opacity in
                panel?.alphaValue = CGFloat(opacity)
                ScreenshotPinEngine.shared.setOpacity(id: pinItem.id, opacity: opacity)
            }
        )

        panel.contentView = NSHostingView(rootView: view)
        panel.orderFrontRegardless()
        windows[pinItem.id] = panel
        activePinCount = windows.count
    }

    public func closePin(id: UUID) {
        if let panel = windows.removeValue(forKey: id) {
            panel.orderOut(nil)
            ScreenshotPinEngine.shared.removePin(id: id)
            activePinCount = windows.count
        }
    }

    public func closeAll() {
        for (_, panel) in windows {
            panel.orderOut(nil)
        }
        windows.removeAll()
        for pin in ScreenshotPinEngine.shared.pins {
            ScreenshotPinEngine.shared.removePin(id: pin.id)
        }
        activePinCount = 0
    }
}

public struct PinnedMomentView: View {
    public let item: PinnedItem
    public let text: String
    public let image: NSImage?
    public var onClose: () -> Void
    public var onOpacityChange: (Double) -> Void

    @State private var currentOpacity: Double = 1.0

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.orange)

                Text(item.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                // Opacity Cycle Button
                Button(action: cycleOpacity) {
                    Text("\(Int(currentOpacity * 100))%")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                }
                .buttonStyle(.plain)

                // Copy Text Button
                Button(action: copyContent) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                // Close Button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.4))

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let image = image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if !text.isEmpty {
                        Text(text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.9))
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cycleOpacity() {
        if currentOpacity >= 1.0 {
            currentOpacity = 0.75
        } else if currentOpacity >= 0.75 {
            currentOpacity = 0.50
        } else if currentOpacity >= 0.50 {
            currentOpacity = 0.25
        } else {
            currentOpacity = 1.0
        }
        onOpacityChange(currentOpacity)
    }

    private func copyContent() {
        NSPasteboard.general.clearContents()
        if !text.isEmpty {
            NSPasteboard.general.setString(text, forType: .string)
        }
    }
}
