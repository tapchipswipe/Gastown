import SwiftUI
import AppKit
import NewtonCore
import NewtonWorkspace

public struct VisualTimelineView: View {
    @Bindable var model: WorkspaceModel
    @State private var searchQuery = ""
    @State private var selectedEvent: HistoryEvent?
    @State private var generatedStandup: StandupReport?
    @State private var generatedSOP: SOPReport?
    @State private var showStandupSheet = false
    @State private var showSOPSheet = false
    @Environment(\.colorScheme) private var colorScheme

    public init(model: WorkspaceModel) {
        self.model = model
    }

    @State private var filteredEvents: [HistoryEvent] = []
    @State private var coverage = "Loading database range…"
    @State private var day = Date()

    public var body: some View {
        VStack(spacing: 0) {
            // Top Controls Bar
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Newton Visual Timeline").font(.title2.bold())
                        Text("On-device visual frame timeline with OCR search and automated pipes.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Pipe 1: Synthesize Standup
                    Button {
                        let report = PipeAutomationEngine.synthesizeStandup(
                            events: filteredEvents,
                            projects: model.trackedProjects
                        )
                        generatedStandup = report
                        showStandupSheet = true
                    } label: {
                        Label("Daily Standup Pipe", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    // Pipe 2: Generate SOP
                    Button {
                        let report = PipeAutomationEngine.generateSOP(
                            title: "Desktop Workflow Procedure",
                            recordedActions: filteredEvents
                        )
                        generatedSOP = report
                        showSOPSheet = true
                    } label: {
                        Label("Recorded Procedure", systemImage: "play.square.stack.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                DatePicker("Observation date", selection: $day, displayedComponents: .date)
                Text(coverage).font(.caption).foregroundStyle(.secondary)
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search visual OCR text, apps, or active windows...", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(PanelSurface.controlFill(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(20)

            Divider().opacity(0.3)

            // Timeline Feed
            if filteredEvents.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text(searchQuery.isEmpty ? "No recorded timeline moments yet" : "No frames matching '\(searchQuery)'")
                        .font(.headline)
                    Text("Turn on Activity history or run screen OCR to populate the visual timeline.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredEvents) { event in
                            timelineCard(event)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .task(id: "\(day.timeIntervalSince1970):\(searchQuery):\(model.totalEvents)") {
            filteredEvents = []
            guard let range = Calendar.current.dateInterval(of: .day, for: day) else { return }
            do {
                let result = try await model.observations(from: range.start, to: range.end, query: searchQuery)
                try Task.checkCancellation()
                filteredEvents = result.events
                coverage = "\(result.events.count) observations · \(result.isComplete ? "database range complete" : "truncated at 50,000") · capture gaps unknown"
            } catch { if !Task.isCancelled { coverage = error.localizedDescription } }
        }
        .sheet(isPresented: $showStandupSheet) {
            if let standup = generatedStandup {
                StandupSheetView(report: standup) {
                    showStandupSheet = false
                }
            }
        }
        .sheet(isPresented: $showSOPSheet) {
            if let sop = generatedSOP {
                SOPSheetView(report: sop) {
                    showSOPSheet = false
                }
            }
        }
    }

    private func timelineCard(_ event: HistoryEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconForSource(event.source))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text(event.title)
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            if !event.detail.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("OCR TEXT / CONTEXT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 8) {
                            Button {
                                model.perform(.presentation(.pinText(event.title,event.detail)))
                            } label: {
                                Label("Pin", systemImage: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.orange)
                            }
                            .buttonStyle(.borderless)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(event.detail, forType: .string)
                            } label: {
                                Label("Copy OCR", systemImage: "doc.on.doc")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Text(event.detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .textSelection(.enabled)
                        .lineLimit(4)
                }
                .padding(8)
                .background(Color.black.opacity(colorScheme == .light ? 0.05 : 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text(event.source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .panelCard(cornerRadius: 12)
    }

    private func iconForSource(_ source: String) -> String {
        switch source {
        case "ScreenCapture", "VisionOCR": return "eye.fill"
        case "Activity": return "app.window.checkmark"
        case "Project": return "arrow.triangle.branch"
        case "TimeAtlas": return "iphone"
        default: return "sparkles"
        }
    }
}

private struct StandupSheetView: View {
    let report: StandupReport
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Generated Daily Standup Note", systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Button("Done", action: onDismiss)
            }

            ScrollView {
                Text(report.fullMarkdown)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Copy Markdown to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.fullMarkdown, forType: .string)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 580, height: 440)
    }
}

private struct SOPSheetView: View {
    let report: SOPReport
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(report.title, systemImage: "play.square.stack.fill")
                    .font(.headline)
                Spacer()
                Button("Done", action: onDismiss)
            }

            ScrollView {
                Text(report.markdownSOP)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("Copy SOP to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.markdownSOP, forType: .string)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
        }
        .padding(24)
        .frame(width: 580, height: 440)
    }
}
