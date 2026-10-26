import SwiftUI
import NewtonCore
import NewtonWorkspace

struct AutomaticIntelligenceView: View {
    @Bindable var model: WorkspaceModel
    @State private var roots = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 18) {
                Text("Automatic intelligence").font(.largeTitle.bold())
                Text("Choose capabilities once. Pause All stops collectors and cancels owned agent execution. Destructive cleanup, merging, pushing, messages and publishing stay explicit.")
                ForEach([NewtonFeature.mailFinance,.dailyReports,.projectContext,.overnightAgents]) { feature in
                    Toggle(feature.title,isOn: Binding(get: { model.selectedFeatures.contains(feature) },set: { model.toggle(feature,enabled: $0) }))
                    Text(model.serviceStates[feature]?.reason ?? feature.explanation).font(.caption).foregroundStyle(.secondary)
                }
                if let proposed = model.automation.meetingProposal {
                    Label("Meeting proposed: " + proposed,systemImage: "mic")
                    Button("Start proposed meeting") { Task { await model.startMeeting() } }
                }
                Button("Retry retained transcript writes") { Task { await model.automation.retryTranscriptWrites() } }
                Text("Repository roots").font(.headline)
                TextEditor(text: $roots).frame(height: 90)
                Button("Save repository roots") { Task { await model.automation.saveRoots(roots) } }
                if let report = model.automation.latestReport {
                    Text("Latest automatic daily summary").font(.headline)
                    Text("Generated \(report.generatedAt.formatted()) · \(report.observationCount) observations · \(report.databaseRangeComplete ? "database range complete" : "truncated")").font(.caption)
                    Text(report.markdown).font(.body.monospaced()).textSelection(.enabled)
                } else { Text("Daily summary will run at 08:15 or once after wake when enabled. Missing sources are reported as insufficient evidence.").foregroundStyle(.secondary) }
                Text("Trusted Newton coding queue").font(.headline)
                Text("Committed Automation/backlog.json only. 22:00–08:00, external power, unlocked, idle, acceptable thermal state and fresh quota below 30%. Two jobs/night; 20-minute provider and 15-minute verification caps. Tests, production build and an explicit file-content criterion are required. Changes stay in isolated worktrees for review. No merge or push; future quota is not guaranteed.").font(.caption)
                ForEach(model.automation.jobs) { job in
                    DisclosureGroup(job.item.title + " · " + job.state.rawValue) {
                        Text(job.item.completion.description).font(.caption)
                        if let worktree = job.worktree { Text(worktree).font(.caption.monospaced()).textSelection(.enabled) }
                        Text(job.evidence).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
            }.padding(28)
        }.onAppear { roots = model.automation.repositoryRoots }
    }
}
