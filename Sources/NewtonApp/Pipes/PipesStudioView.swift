import SwiftUI
import NewtonCore
import NewtonWorkspace

public struct PipesStudioView: View {
    @Bindable var model: WorkspaceModel

    public enum ActivePipe: String, CaseIterable, Identifiable, Sendable {
        case missedToDos = "Missed To-Dos Radar"
        case dailyStandup = "Daily Engineering Standup"
        case meetingDigest = "Meeting Digest Synthesizer"
        case sopGenerator = "Video-to-Code SOP Generator"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .missedToDos: return "checklist.checked"
            case .dailyStandup: return "doc.text.below.ecg"
            case .meetingDigest: return "person.3.sequence.fill"
            case .sopGenerator: return "play.square.stack.fill"
            }
        }

        public var description: String {
            switch self {
            case .missedToDos:
                return "Extracts candidate commitment mentions from today’s saved observations; status is unverified."
            case .dailyStandup:
                return "Summarizes saved observations with evidence links and explicit coverage."
            case .meetingDigest:
                return "Extracts key decisions, agreements, and next steps from meeting transcripts or raw conversation notes."
            case .sopGenerator:
                return "Transforms observed workflows and shell executions into step-by-step Standard Operating Procedures."
            }
        }
    }

    @State private var selectedPipe: ActivePipe = .missedToDos
    @State private var inputNotes: String = ""
    @State private var generatedMarkdown: String = ""
    @State private var isExecuting: Bool = false
    @State private var copyFeedback: String?
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screenpipe Deep Pipes Studio").font(.largeTitle.bold())
                        Text("On-device automation pipelines converting recorded screen moments, commits, and audio into structured intelligence.").font(.title3).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                // 4-Card Pipe Selector Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(ActivePipe.allCases) { pipe in
                        pipeCard(pipe)
                    }
                }

                // Pipe Execution Panel
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Label(selectedPipe.rawValue, systemImage: selectedPipe.iconName)
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        Button {
                            executeCurrentPipe()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                Text(isExecuting ? "Executing…" : "Run Pipeline")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExecuting)
                    }

                    Text(selectedPipe.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Optional Input Field for Meeting or Custom Context
                    if selectedPipe == .meetingDigest || selectedPipe == .sopGenerator {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(selectedPipe == .meetingDigest ? "Meeting Notes or Transcript:" : "Workflow Context / Description:")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)

                            TextEditor(text: $inputNotes)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(height: 80)
                                .padding(6)
                                .background(PanelSurface.controlFill(for: colorScheme))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }

                    // Output Viewer
                    if !generatedMarkdown.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("PIPELINE SYNTHESIS OUTPUT")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let feedback = copyFeedback {
                                    Text(feedback)
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.green)
                                }

                                Button {
                                    copyToClipboard()
                                } label: {
                                    Label("Copy Markdown", systemImage: "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    saveMarkdownToFile()
                                } label: {
                                    Label("Save to File", systemImage: "arrow.down.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            ScrollView {
                                Text(generatedMarkdown)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(PanelSurface.controlFill(for: colorScheme))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .frame(maxHeight: 320)
                        }
                    }
                }
                .panelCard(cornerRadius: 14)
            }
            .padding(28)
        }
        .task(id: model.requestedReport) {
            if let name = model.requestedReport, let pipe = ActivePipe(rawValue: name) {
                selectedPipe = pipe; model.requestedReport = nil; executeCurrentPipe()
            }
        }
    }

    private func pipeCard(_ pipe: ActivePipe) -> some View {
        Button {
            selectedPipe = pipe
            copyFeedback = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: pipe.iconName)
                    .font(.system(size: 24))
                    .foregroundStyle(selectedPipe == pipe ? Color.accentColor : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(pipe.rawValue)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(selectedPipe == pipe ? Color.accentColor : Color.primary)
                    Text(pipe.description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selectedPipe == pipe ? Color.accentColor.opacity(0.12) : PanelSurface.controlFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selectedPipe == pipe ? Color.accentColor : PanelSurface.border(for: colorScheme), lineWidth: selectedPipe == pipe ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func executeCurrentPipe() {
        guard !isExecuting else { return }
        isExecuting = true
        copyFeedback = nil

        let currentPipe = selectedPipe
        let projects = model.trackedProjects
        let notes = inputNotes

        Task {
            defer { isExecuting = false }
            var output = ""
            let day = Calendar.current.dateInterval(of: .day, for: Date())!
            let result: DailyHistoryResult
            do { result = try await model.observations(from: day.start, to: day.end) }
            catch { generatedMarkdown = "Report unavailable: " + error.localizedDescription; return }
            let events = result.events

            switch currentPipe {
            case .missedToDos:
                let report = PipeAutomationEngine.synthesizeMissedToDos(events: events)
                output = report.fullMarkdown

            case .dailyStandup:
                let report = PipeAutomationEngine.synthesizeStandup(
                    events: events,
                    projects: projects
                )
                output = report.fullMarkdown

            case .meetingDigest:
                let text = notes
                let report = PipeAutomationEngine.synthesizeMeetingDigest(title: "Architecture Sync", notes: text)
                output = report.fullMarkdown

            case .sopGenerator:
                let title = "Developer Build & Verification SOP"
                let actions = events.filter { $0.source == "Activity" || $0.source == "ScreenCapture" }
                let report = PipeAutomationEngine.generateSOP(
                    title: title,
                    recordedActions: actions.isEmpty ? events : actions
                )
                output = report.markdownSOP
            }

            self.generatedMarkdown = "Range: \(day.start.ISO8601Format()) to \(day.end.ISO8601Format())\n\nDatabase range \(result.isComplete ? "complete" : "truncated at 50,000 observations"); capture gaps unknown.\n\n" + output
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedMarkdown, forType: .string)
        copyFeedback = "Copied to clipboard!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.copyFeedback = nil
        }
    }

    private func saveMarkdownToFile() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "Pipe_Report_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).md"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? generatedMarkdown.write(to: url, atomically: true, encoding: .utf8)
                copyFeedback = "Saved report to \(url.lastPathComponent)!"
            }
        }
    }
}
