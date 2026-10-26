import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

public struct CommandBarView: View {
    @Bindable var model: WorkspaceModel
    var onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var isFieldFocused: Bool
    @State private var selectedIndex = 0
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel, onDismiss: @escaping () -> Void) {
        self.model = model
        self.onDismiss = onDismiss
    }

    private var mathResult: String? {
        CommandBarEngine.evaluateMath(query)
    }

    private var unitResult: String? {
        CommandBarEngine.convertUnits(query)
    }

    private var matchedActions: [CommandBarAction] {
        CommandBarEngine.matchActions(query: query)
    }

    private var matchedProjects: [TrackedProject] {
        guard !query.isEmpty else { return model.trackedProjects }
        return model.trackedProjects.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.activeBranch.localizedCaseInsensitiveContains(query)
        }
    }

    private var matchedWindows: [SwitchableWindow] {
        guard !query.isEmpty else { return [] }
        return WindowSwitcherEngine.captureWindows().filter {
            $0.appName.localizedCaseInsensitiveContains(query) ||
            $0.windowTitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var matchedMoments: [HistoryEvent] {
        guard !query.isEmpty else { return [] }
        return Array(model.events.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.detail.localizedCaseInsensitiveContains(query)
        }.prefix(4))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Search Input Field
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                TextField("Type a command, calculation (2+2*3), conversion (100 km to mi), or project...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .focused($isFieldFocused)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Esc") {
                    onDismiss()
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().opacity(0.2)

            // Dynamic Math or Conversion Result Banner
            if let result = mathResult ?? unitResult {
                HStack {
                    Image(systemName: "equal.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.green)
                    Text(result)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Copy") {
                        let clean = result.replacingOccurrences(of: "= ", with: "")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(clean, forType: .string)
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.green.opacity(0.12))
            }

            // Results List
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Actions Section
                    if !matchedActions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ACTIONS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            ForEach(matchedActions) { action in
                                actionRow(action)
                            }
                        }
                    }

                    // Open Windows Section
                    if !matchedWindows.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OPEN WINDOWS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            ForEach(matchedWindows) { window in
                                windowRow(window)
                            }
                        }
                    }

                    // Tracked Projects Section
                    if !matchedProjects.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DEVELOPMENT REPOSITORIES")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            ForEach(matchedProjects) { project in
                                projectRow(project)
                            }
                        }
                    }

                    // Screenpipe OCR Moments Section
                    if !matchedMoments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SCREENPIPE OCR MOMENTS")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 16)

                            ForEach(matchedMoments) { moment in
                                momentRow(moment)
                            }
                        }
                    }
                }
                .padding(.vertical, 10)
            }

            Divider().opacity(0.2)

            // Footer
            HStack {
                Text("Newton ⌘K Super-App Palette")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 12) {
                    Text("↵ Execute")
                    Text("⎋ Dismiss")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.1))
        }
        .background(
            ZStack {
                HUDBackdrop(cornerRadius: 18)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 1)
        )
        .onAppear {
            isFieldFocused = true
        }
    }

    private func actionRow(_ action: CommandBarAction) -> some View {
        Button {
            executeAction(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 12, weight: .medium))
                    Text(action.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(action.category)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ project: TrackedProject) -> some View {
        Button {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: project.path)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name).font(.system(size: 12, weight: .medium))
                        Text(project.activeBranch).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Text(project.path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func windowRow(_ window: SwitchableWindow) -> some View {
        Button {
            WindowSwitcherEngine.activate(window: window)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "macwindow")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(window.appName).font(.system(size: 12, weight: .bold))
                        if !window.windowTitle.isEmpty {
                            Text(window.windowTitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                Text("Switch")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func momentRow(_ moment: HistoryEvent) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(moment.detail.isEmpty ? moment.title : moment.detail, forType: .string)
            onDismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(moment.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if !moment.detail.isEmpty {
                        Text(moment.detail)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(moment.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy moment text to clipboard")
    }

    private func executeAction(_ action: CommandBarAction) {
        switch action.id {
        case "standup":
            model.perform(.report("Daily Engineering Standup"))
            onDismiss()
        case "missedTodos":
            model.perform(.report("Missed To-Dos Radar"))
            onDismiss()
        case "snapLeft":
            model.perform(.snap(.leftHalf))
            onDismiss()
        case "snapRight":
            model.perform(.snap(.rightHalf))
            onDismiss()
        case "snapMax":
            model.perform(.snap(.maximize))
            onDismiss()
        case "snapCenter":
            model.perform(.snap(.center))
            onDismiss()
        case "ports":
            model.perform(.navigate("Developer Ports"))
            onDismiss()
        case "ghostStorage":
            model.perform(.navigate("iCloud & Storage"))
            onDismiss()
        case "bloat":
            model.perform(.scanCleanup)
            onDismiss()
        case "keepAwake":
            model.perform(.toggleAwake)
            onDismiss()
        case "eyedropper":
            model.perform(.presentation(.sampleColor))
            onDismiss()
        case "mute":
            model.perform(.presentation(.muteMicrophone))
            onDismiss()
        case "notch":
            NotchWindowController.shared.configure(with: model)
            model.perform(.presentation(.notch))
            onDismiss()
        case "hud":
            DesktopHUDWindowController.shared.configure(with: model)
            model.perform(.presentation(.hud))
            onDismiss()
        case "shelf":
            model.perform(.presentation(.shelf))
            onDismiss()
        case "cleanMode":
            model.perform(.toggleCleaning)
            onDismiss()
        case "pinMoment":
            model.perform(.presentation(.pinLatest))
            onDismiss()
        case "closePins":
            model.perform(.presentation(.closePins))
            onDismiss()
        case "quitProtect":
            model.perform(.toggleQuitProtection)
            onDismiss()
        default:
            onDismiss()
        }
    }
}
