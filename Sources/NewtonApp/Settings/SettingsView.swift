import SwiftUI
import NewtonCore
import NewtonWorkspace

public enum SettingsTab: String, CaseIterable, Identifiable {
    case featureHub = "Feature Hub"
    case shortcuts = "Shortcuts"
    case power = "Apple Silicon Power"
    case protection = "Quit & Clean Mode"
    case privacy = "Privacy & Storage"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .featureHub: return "square.grid.2x2.fill"
        case .shortcuts: return "keyboard"
        case .power: return "cpu"
        case .protection: return "shield.checkered"
        case .privacy: return "hand.raised.fill"
        }
    }
}

public struct SettingsView: View {
    @State private var protectedAppsText = ""
    @Bindable var model: WorkspaceModel
    @State private var selectedTab: SettingsTab = .featureHub
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.iconName)
                }
            }
            .navigationTitle("Newton Settings")
            .frame(minWidth: 200)
        } detail: {
            switch selectedTab {
            case .featureHub:
                featureHubSettings
            case .shortcuts:
                shortcutsSettings
            case .power:
                powerSettings
            case .protection:
                protectionSettings
            case .privacy:
                PrivacyView(model: model)
                    .padding(24)
            }
        }
        .frame(minWidth: 680, minHeight: 460)
    }

    // MARK: - Tab 1: Feature Hub
    private var featureHubSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modular Feature Hub").font(.title2.bold())
                    Text("Configure and toggle capabilities across the Newton super-app suite.").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    featureToggleRow(
                        title: "Vorssaint Dynamic Notch & Island",
                        description: "Floating liquid-glass drawer on camera notch with AI quota, equalizer, and scratchpad.",
                        systemImage: "macbook.gen2",
                        isOn: Binding(
                            get: { NotchWindowController.shared.isVisible },
                            set: { if $0 { NotchWindowController.shared.show() } else { NotchWindowController.shared.hide() } }
                        )
                    )

                    featureToggleRow(
                        title: "Vorssaint Fast Window Switcher (⌥Tab)",
                        description: "Instant thumbnail window switcher cycling active macOS application windows.",
                        systemImage: "macwindow.on.rectangle",
                        isOn: .constant(true)
                    )

                    featureToggleRow(
                        title: "Vorssaint Radial Quick Menu (⌃⌥R)",
                        description: "8-slice radial action wheel summoned under mouse cursor for rapid window management.",
                        systemImage: "circle.circle.fill",
                        isOn: .constant(true)
                    )

                    featureToggleRow(
                        title: "Screenpipe On-Device OCR",
                        description: "Whole-display sampled-image digest with periodic local OCR; resource use depends on enabled capture.",
                        systemImage: "text.viewfinder",
                        isOn: Binding(
                            get: { model.enabled.contains(.screenOCR) },
                            set: { model.toggle(.screenOCR, enabled: $0) }
                        )
                    )

                    featureToggleRow(
                        title: "Screenpipe Speech & Meeting Transcription",
                        description: "100% On-device Apple Speech transcription with zero cloud egress.",
                        systemImage: "waveform",
                        isOn: .constant(true)
                    )

                    featureToggleRow(
                        title: "Lumen Receipt-observed spending",
                        description: "Receipt intake acceptance pending; financial totals unavailable.",
                        systemImage: "banknote.fill",
                        isOn: .constant(true)
                    )

                    featureToggleRow(
                        title: "Lumen 6-Pillar iCloud Optimizer",
                        description: "Proactive cloud ghost eviction, developer bloat trimming, and 1-click turbo sweep.",
                        systemImage: "cloud.fill",
                        isOn: .constant(true)
                    )

                    featureToggleRow(
                        title: "Keep Awake Idle Sleep Prevention",
                        description: "Prevents display and system sleep while active.",
                        systemImage: "cup.and.saucer.fill",
                        isOn: Binding(
                            get: { model.enabled.contains(.keepAwake) },
                            set: { model.toggle(.keepAwake, enabled: $0) }
                        )
                    )
                }
            }
            .padding(24)
        }
    }

    private func featureToggleRow(title: String, description: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold))
                Text(description).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(12)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Tab 2: Shortcuts
    private var shortcutsSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Global System Hotkeys").font(.title2.bold())
                    Text("Global shortcuts registered with Carbon; conflicts and installation failures are shown.").font(.caption).foregroundStyle(.secondary)
                }

                VStack(spacing: 8) {
                    shortcutRow(title: "Command Palette", shortcut: "⌥ Space")
                    shortcutRow(title: "Menu Panel Quick View", shortcut: "⌃ ⌘ V")
                    shortcutRow(title: "Window Switcher", shortcut: "⌥ Tab")
                    shortcutRow(title: "Radial Action Wheel", shortcut: "⌃ ⌥ R")
                    shortcutRow(title: "Dynamic Notch Island", shortcut: "⌃ ⌥ N")
                    shortcutRow(title: "Desktop Glass HUD", shortcut: "⌃ ⌥ H")
                    shortcutRow(title: "Snap Window Left", shortcut: "⌃ ⌥ ←")
                    shortcutRow(title: "Snap Window Right", shortcut: "⌃ ⌥ →")
                    shortcutRow(title: "Snap Window Maximize", shortcut: "⌃ ⌥ ↩")
                    shortcutRow(title: "Snap Window Center", shortcut: "⌃ ⌥ C")
                }
            }
            .padding(24)
        }
    }

    private func shortcutRow(title: String, shortcut: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .medium))
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(PanelSurface.controlFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Tab 3: Power
    private var powerSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Battery telemetry").font(.title2.bold())
                    Text("IOKit AppleSmartBattery power telemetry and battery discharge pacing.").font(.caption).foregroundStyle(.secondary)
                }

                let power = PowerPacingEngine.captureSnapshot()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Battery discharge estimate:")
                        Spacer()
                        Text(power.estimatedWatts.map { String(format: "%.1f W", $0) } ?? "Unavailable")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    HStack {
                        Text("Battery Runway:")
                        Spacer()
                        Text(power.runwayFormatted)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    HStack {
                        Text("Thermal State:")
                        Spacer()
                        Text(power.thermalState)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    if let cycles = power.cycleCount {
                        HStack {
                            Text("Battery Cycle Count:")
                            Spacer()
                            Text("\(cycles)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                        }
                    }
                }
                .padding(16)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(24)
        }
    }

    // MARK: - Tab 4: Protection & Cleaning
    private var protectionSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Accidental Quit Protection & Cleaning Mode").font(.title2.bold())
                    Text("Intercept accidental ⌘Q / ⌘W presses and lock keyboard for wiping down your Mac.").font(.caption).foregroundStyle(.secondary)
                }

                // Section 1: Quit Protection
                VStack(alignment: .leading, spacing: 14) {
                    Text("⌘Q / ⌘W Quit Protection").font(.headline)

                    Toggle(
                        "Enable Accidental Quit Protection",
                        isOn: Binding(
                            get: { model.keyboard.quitEnabled },
                            set: { model.setQuitProtection($0) }
                        )
                    )

                    Text(model.keyboard.state.reason).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hold Duration: \(String(format: "%.1f", QuitProtectionEngine.shared.config.holdDurationSeconds))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Slider(
                            value: Binding(
                                get: { QuitProtectionEngine.shared.config.holdDurationSeconds },
                                set: { model.setHoldDuration($0) }
                            ),
                            in: 0.4...2.0,
                            step: 0.1
                        )
                    }

                    Toggle("Keep awake while Focus Shield is on",isOn: Binding(get: { model.focusShieldKeepsAwake },set: { model.setFocusShieldWake($0) }))
                    Text("Protected Applications:")
                        .font(.caption.bold())

                    TextEditor(text: $protectedAppsText).frame(height: 90)
                        .onAppear { protectedAppsText = QuitProtectionEngine.shared.config.protectedBundleIDs.sorted().joined(separator: "\n") }
                    Button("Save Protected Applications") { model.setProtectedApplications(protectedAppsText) }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(QuitProtectionEngine.shared.config.protectedBundleIDs).sorted(), id: \.self) { bundleID in
                            HStack {
                                Image(systemName: "shield.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.green)
                                Text(bundleID)
                                    .font(.system(size: 11, design: .monospaced))
                                Spacer()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(16)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Section 2: Cleaning Mode
                VStack(alignment: .leading, spacing: 14) {
                    Text("Keyboard Cleaning Mode").font(.headline)

                    Text("Locks all keyboard input so you can safely wipe your MacBook screen and keys. Mouse clicks remain active. Press Escape 5 times or click Unlock to exit.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Keep Screen Visible (Translucent Overlay instead of Full Blackout)",
                        isOn: Binding(
                            get: { CleaningModeEngine.shared.keepScreenVisible },
                            set: { model.setCleaningScreenVisible($0) }
                        )
                    )

                    Button("Enter Cleaning Mode Now") {
                        CleaningModeController.shared.enterCleaningMode()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(16)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Section 3: Floating Pins
                VStack(alignment: .leading, spacing: 14) {
                    Text("Floating Screenshot & Moment Pins").font(.headline)

                    HStack {
                        Text("Active Desktop Pins: \(ScreenshotPinController.shared.activePinCount)")
                            .font(.subheadline)
                        Spacer()
                        if ScreenshotPinController.shared.activePinCount > 0 {
                            Button("Close All Pins") {
                                ScreenshotPinController.shared.closeAll()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(24)
        }
    }
}
