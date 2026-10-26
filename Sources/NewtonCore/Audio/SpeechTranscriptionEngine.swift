import Foundation
import Speech
import AVFoundation
import Observation

public struct TranscriptSegment: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let confidence: Double
    public let isFinal: Bool
    public let sourceChannel: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), text: String, confidence: Double = 1.0, isFinal: Bool = true, sourceChannel: String = "microphone") {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.confidence = confidence
        self.isFinal = isFinal; self.sourceChannel = sourceChannel
    }
}

public struct MeetingTranscriptRecord: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let meetingTitle: String
    public let startTime: Date
    public let endTime: Date
    public let segments: [TranscriptSegment]
    public let fullTranscript: String
    public let actionItems: [String]

    public init(
        id: UUID = UUID(),
        meetingTitle: String,
        startTime: Date = Date(),
        endTime: Date = Date(),
        segments: [TranscriptSegment] = [],
        fullTranscript: String = "",
        actionItems: [String] = []
    ) {
        self.id = id
        self.meetingTitle = meetingTitle
        self.startTime = startTime
        self.endTime = endTime
        self.segments = segments
        self.fullTranscript = fullTranscript
        self.actionItems = actionItems
    }
}

/// Replaces the overlapping hypothesis for a recognition task; finalization preserves identity.
public struct TranscriptAccumulator: Sendable {
    public private(set) var segments: [TranscriptSegment] = []
    private var id = UUID()
    private let channel: String
    public init(channel: String = "microphone") { self.channel = channel }
    public mutating func beginSegment() { id = UUID() }
    public mutating func update(_ text: String,isFinal: Bool,timestamp: Date = Date()) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let previous = segments.last
        if previous?.id == id && previous?.isFinal == true { return }
        let segment = TranscriptSegment(id: id,timestamp: previous?.id == id ? previous!.timestamp : timestamp,text: text,confidence: 0,isFinal: isFinal,sourceChannel: channel)
        if previous?.id == id { segments[segments.count-1] = segment } else { segments.append(segment) }
    }
}

@MainActor @Observable public final class SpeechTranscriptionEngine {
    public static let shared = SpeechTranscriptionEngine()
    public private(set) var isRecording = false
    public private(set) var diagnostic = "Off · microphone only; system audio unavailable"
    public private(set) var transcript = TranscriptAccumulator()
    public var onRecord: (@MainActor (MeetingTranscriptRecord) -> Void)?
    @ObservationIgnored private var audioEngine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var audioSink: SpeechAudioSink?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionID = UUID()
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var permissionTask: Task<Void,Never>?
    private var title = "Meeting"
    private var start = Date()
    public init() {}
    nonisolated public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { SFSpeechRecognizer.authorizationStatus() }
    nonisolated public static func requireLocalSupport(authorized: Bool, available: Bool, onDevice: Bool) throws {
        guard authorized, available, onDevice else { throw StoreError(message: "Authorized, available on-device speech recognition is required. Cloud fallback is disabled.") }
    }
    public func requestPermissionsAndStart(title: String = "Meeting", mayStart: @MainActor () -> Bool = { true }) async {
        let speech = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) } }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard speech && microphone else { diagnostic = "Blocked · microphone and speech permission required"; return }
        guard mayStart() else { diagnostic = "Paused before recording started"; return }
        do { try startLiveMeeting(title: title) } catch { diagnostic = error.localizedDescription }
    }
    public func startLiveMeeting(title: String = "Meeting") throws {
        guard !isRecording else { return }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        try Self.requireLocalSupport(authorized: Self.authorizationStatus() == .authorized && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            available: recognizer?.isAvailable == true, onDevice: recognizer?.supportsOnDeviceRecognition == true)
        guard let recognizer else { throw StoreError(message: "On-device speech recognizer unavailable") }
        let engine = AVAudioEngine(), request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true; request.requiresOnDeviceRecognition = true
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw StoreError(message: "Microphone audio format unavailable") }
        let sink = SpeechAudioSink(request)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }
        do { engine.prepare(); try engine.start() }
        catch { engine.inputNode.removeTap(onBus: 0); engine.stop(); throw error }
        self.audioEngine = engine; self.request = request; self.audioSink = sink; self.recognizer = recognizer; self.title = title; start = Date()
        transcript = TranscriptAccumulator(); epoch = UUID(); let id = epoch
        isRecording = true; diagnostic = "Recording · on-device microphone only; no system audio"
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self,self.epoch == id,self.isRecording else { return }
                if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized || Self.authorizationStatus() != .authorized || self.audioEngine?.isRunning != true {
                    self.stopLiveMeeting(); self.diagnostic = "Stopped · microphone engine unavailable or permission lost"; return
                }
            }
        }
        startRecognition(request,session: id)
    }
    private func startRecognition(_ request: SFSpeechAudioBufferRecognitionRequest,session: UUID) {
        recognitionID = UUID(); let current = recognitionID
        task = recognizer?.recognitionTask(with: request) { [weak self] result,error in
            let text = result?.bestTranscription.formattedString,final = result?.isFinal ?? false,failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self,self.epoch == session,self.recognitionID == current,self.isRecording else { return }
                if let text { self.transcript.update(text,isFinal: final) }
                if let failure { self.stopLiveMeeting(); self.diagnostic = "Recognition stopped: " + failure; return }
                if final {
                    let next = SFSpeechAudioBufferRecognitionRequest(); next.requiresOnDeviceRecognition = true; next.shouldReportPartialResults = true
                    self.transcript.beginSegment(); self.request = next; self.audioSink?.replace(next)
                    self.startRecognition(next,session: session)
                }
            }
        }
    }
    @discardableResult public func stopLiveMeeting() -> MeetingTranscriptRecord {
        epoch = UUID(); permissionTask?.cancel(); permissionTask = nil
        audioEngine?.stop(); audioEngine?.inputNode.removeTap(onBus: 0); audioEngine = nil
        audioSink?.stop(); audioSink = nil; recognizer = nil
        request?.endAudio(); request = nil; task?.cancel(); task = nil
        let wasRecording = isRecording; isRecording = false; diagnostic = "Stopped · microphone only"
        let text = transcript.segments.map(\.text).joined(separator: " ")
        let record = MeetingTranscriptRecord(meetingTitle: title, startTime: start, endTime: Date(), segments: transcript.segments, fullTranscript: text, actionItems: Self.extractActionItems(from: text))
        if wasRecording { onRecord?(record) }
        return record
    }

    /// Pure offline synthesizer: analyzes transcript text for actionable commitments, deadlines, and TODOs.
    nonisolated public static func extractActionItems(from transcript: String) -> [String] {
        let lines = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        var items: [String] = []

        let actionKeywords = ["todo", "will do", "need to", "action item", "follow up", "assign", "ship", "fix", "deadline"]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let lower = trimmed.lowercased()
            for keyword in actionKeywords {
                if lower.contains(keyword) {
                    items.append(trimmed)
                    break
                }
            }
        }

        return items
    }
}
