import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import Speech
import Observation

/// SFSpeech requests accept audio from a serial capture queue. A lock serializes append
/// with request detachment; no AV buffer or CMSampleBuffer crosses an actor boundary.
final class SpeechAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) { lock.withLock { request?.append(buffer) } }
    func replace(_ next: SFSpeechAudioBufferRecognitionRequest) { lock.withLock { request?.endAudio(); request = next } }
    func append(_ sample: CMSampleBuffer) {
        guard let description = CMSampleBufferGetFormatDescription(sample), CMSampleBufferDataIsReady(sample) else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = CMSampleBufferGetNumSamples(sample)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample,at: 0,frameCount: Int32(frames),into: buffer.mutableAudioBufferList) == noErr else { return }
        lock.withLock { request?.append(buffer) }
    }
    func stop() { lock.withLock { request?.endAudio(); request = nil } }
}
private final class SystemAudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sink: SpeechAudioSink
    let failed: @Sendable (String) -> Void
    init(sink: SpeechAudioSink, failed: @escaping @Sendable (String) -> Void) { self.sink = sink; self.failed = failed }
    func stream(_ stream: SCStream,didOutputSampleBuffer sampleBuffer: CMSampleBuffer,of outputType: SCStreamOutputType) {
        if outputType == .audio { sink.append(sampleBuffer) }
    }
    func stream(_ stream: SCStream,didStopWithError error: any Error) { failed(error.localizedDescription) }
}

@MainActor @Observable public final class SystemAudioTranscriber {
    public private(set) var isRecording = false
    public private(set) var diagnostic = "System audio off"
    public private(set) var transcript = TranscriptAccumulator(channel: "system")
    public var onRecord: (@MainActor (MeetingTranscriptRecord) -> Void)?
    @ObservationIgnored private var stopTask: Task<Void,Never>?
    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: SystemAudioOutput?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionID = UUID()
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var permissionTask: Task<Void,Never>?
    private var started = Date()
    public init() {}
    public func start(mayStart: @MainActor () -> Bool) async {
        if let stopTask { await stopTask.value }
        guard !isRecording else { return }
        epoch = UUID(); let id = epoch
        guard CGPreflightScreenCaptureAccess() else { diagnostic = "Microphone-only coverage · Screen Recording required for system audio"; return }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        do {
            try SpeechTranscriptionEngine.requireLocalSupport(authorized: SFSpeechRecognizer.authorizationStatus() == .authorized,available: recognizer?.isAvailable == true,onDevice: recognizer?.supportsOnDeviceRecognition == true)
            let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly: true)
            guard let display = content.displays.first, mayStart(), epoch == id else { return }
            let request = SFSpeechAudioBufferRecognitionRequest(); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
            let sink = SpeechAudioSink(request)
            let output = SystemAudioOutput(sink: sink) { [weak self] reason in Task { @MainActor [weak self] in
                guard let self,self.epoch == id else { return }; await self.stop(); self.diagnostic = "System audio stopped: " + reason
            } }
            let config = SCStreamConfiguration(); config.width = 2; config.height = 2
            config.minimumFrameInterval = CMTime(seconds: 1,preferredTimescale: 600)
            config.capturesAudio = true; config.excludesCurrentProcessAudio = true; config.sampleRate = 16000; config.channelCount = 1
            let stream = SCStream(filter: SCContentFilter(display: display,excludingWindows: []),configuration: config,delegate: output)
            try stream.addStreamOutput(output,type: .audio,sampleHandlerQueue: DispatchQueue(label: "Newton.system-audio"))
            self.stream = stream; self.output = output; transcript = TranscriptAccumulator(channel: "system"); started = Date()
            self.recognizer = recognizer
            startRecognition(request,session: id)
            try await stream.startCapture()
            guard epoch == id,mayStart() else { await stop(); return }
            isRecording = true; diagnostic = "On-device system audio · own-process audio excluded · separate channel"
            permissionTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self,self.epoch == id else { return }
                    if !CGPreflightScreenCaptureAccess() || SFSpeechRecognizer.authorizationStatus() != .authorized {
                        await self.stop(); self.diagnostic = "System audio stopped · permission lost"; return
                    }
                }
            }
        } catch { await stop(); diagnostic = "Microphone-only coverage · " + error.localizedDescription }
    }
    private func startRecognition(_ request: SFSpeechAudioBufferRecognitionRequest,session: UUID) {
        recognitionID = UUID(); let current = recognitionID
        recognition = recognizer?.recognitionTask(with: request) { [weak self] result,error in
            let text = result?.bestTranscription.formattedString,final = result?.isFinal ?? false,failure = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self,self.epoch == session,self.recognitionID == current else { return }
                if let text { self.transcript.update(text,isFinal: final) }
                if let failure { await self.stop(); self.diagnostic = failure; return }
                if final {
                    let next = SFSpeechAudioBufferRecognitionRequest(); next.requiresOnDeviceRecognition = true; next.shouldReportPartialResults = true
                    self.transcript.beginSegment(); self.output?.sink.replace(next); self.startRecognition(next,session: session)
                }
            }
        }
    }
    public func stop() async {
        if let stopTask { await stopTask.value; return }
        let task = Task { await self.finishStopping() }; stopTask = task
        await task.value; stopTask = nil
    }
    private func finishStopping() async {
        epoch = UUID(); permissionTask?.cancel(); permissionTask = nil
        let stream = stream; self.stream = nil; output?.sink.stop(); output = nil
        recognition?.cancel(); recognition = nil; recognizer = nil
        let active = isRecording; isRecording = false
        if let stream { try? await stream.stopCapture() }
        if active {
            let text = transcript.segments.map(\.text).joined(separator: " ")
            onRecord?(MeetingTranscriptRecord(meetingTitle: "Meeting · system audio",startTime: started,endTime: Date(),segments: transcript.segments,fullTranscript: text,actionItems: SpeechTranscriptionEngine.extractActionItems(from: text)))
        }
        diagnostic = "System audio stopped"
    }
}
