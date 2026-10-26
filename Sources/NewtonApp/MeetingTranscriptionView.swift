import SwiftUI
import NewtonCore
import NewtonWorkspace

struct MeetingTranscriptionView: View {
    @Bindable var model: WorkspaceModel
    @State private var expandedSource: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 16) {
                Text("On-device meeting transcription").font(.title.bold())
                Text(model.speech.diagnostic).foregroundStyle(.secondary)
                Text(model.automation.transcriptWriteDiagnostic).font(.caption).foregroundStyle(.secondary)
                Text(model.systemSpeech.diagnostic).font(.caption).foregroundStyle(.secondary)
                Text("Raw audio stays transient. Channels retain separate source identities. Lock, sleep, Pause All, permission loss or recognition failure stops recording. Action mentions are candidates requiring review.")
                Toggle("Include system audio when available",isOn: $model.includeSystemAudio).onChange(of: model.includeSystemAudio) { model.saveMeetingPreferences() }
                Toggle("Propose meetings when Zoom, Teams or FaceTime is running",isOn: Binding(get: { model.automation.detectMeetings },set: { model.automation.detectMeetings = $0 })).onChange(of: model.automation.detectMeetings) { model.saveMeetingPreferences() }
                Toggle("Automatically record detected meetings (separate opt-in)",isOn: Binding(get: { model.automation.automaticallyRecordMeetings },set: { model.automation.automaticallyRecordMeetings = $0 })).onChange(of: model.automation.automaticallyRecordMeetings) { model.saveMeetingPreferences() }
                Button(model.speech.isRecording ? "Stop Transcription" : "Start Transcription") {
                    if model.speech.isRecording { model.stopMeeting() } else { Task { await model.startMeeting() } }
                }.buttonStyle(.borderedProminent)
                evidence(model.speech.transcript.segments,channel: "Microphone")
                evidence(model.systemSpeech.transcript.segments,channel: "System audio")
            }.padding(28)
        }
    }
    private func evidence(_ segments: [TranscriptSegment],channel: String) -> some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(channel).font(.headline)
            ForEach(segments) { segment in
                VStack(alignment: .leading,spacing: 8) {
                    DisclosureGroup(isExpanded: Binding(get: { expandedSource == segment.id },set: { expandedSource = $0 ? segment.id : nil })) {
                        Text(segment.text).textSelection(.enabled)
                        Text("Source segment: " + segment.id.uuidString + " · " + segment.sourceChannel).font(.caption.monospaced()).textSelection(.enabled)
                    } label: { Text(segment.isFinal ? "Final transcript segment" : "Partial hypothesis") }
                    if segment.isFinal {
                        ForEach(Array(Set(SpeechTranscriptionEngine.extractActionItems(from: segment.text))).sorted(),id: \.self) { candidate in
                            Text("Action candidate · status unverified: " + candidate)
                            Button("View contributing transcript") { expandedSource = segment.id }.font(.caption)
                        }
                    }
                }
            }
        }
    }
}
