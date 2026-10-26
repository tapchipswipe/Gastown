import Foundation
import CoreGraphics
import CryptoKit
import Carbon.HIToolbox
import Vision
import ScreenCaptureKit

public struct CapturePrivacyBlocked: Error, Sendable {
    public let reason: String
    public init(_ reason: String) { self.reason = reason }
}

/// A recognized line of text on screen with its bounding box and confidence score.
public struct RecognizedTextLine: Sendable, Codable, Equatable {
    public let text: String
    public let confidence: Float
    /// Normalized coordinates: [x, y, width, height] where 0.0 to 1.0 represents the full image bounds.
    public let boundingBox: [Double]

    public init(text: String, confidence: Float, boundingBox: [Double] = []) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// A captured screen frame with on-device text recognition and metadata.
public struct RecognizedScreenFrame: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let appName: String
    public let windowTitle: String
    public let fullText: String
    public let lines: [RecognizedTextLine]

    public init(
        id: String = UUID().uuidString,
        timestamp: Date = Date(),
        appName: String,
        windowTitle: String = "",
        fullText: String,
        lines: [RecognizedTextLine] = []
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.fullText = fullText
        self.lines = lines
    }

    /// Converts the OCR screen frame into a standard Newton `HistoryEvent`.
    public func asHistoryEvent() -> HistoryEvent {
        let displayTitle = windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)"
        return HistoryEvent(
            id: "screenpipe:ocr:\(id)",
            timestamp: timestamp,
            source: "Newton · Main display OCR",
            title: String(displayTitle.prefix(4000)),
            detail: String(fullText.prefix(12_000))
        )
    }
}

/// Protocol for running text recognition on a CGImage.
public protocol TextRecognizing: Sendable {
    func recognizeText(in image: CGImage) throws -> [RecognizedTextLine]
}

/// On-device Apple Vision OCR; hardware execution is chosen by the framework.
public final class AppleVisionTextRecognizer: TextRecognizing, @unchecked Sendable {
    public let fast: Bool
    public let minimumConfidence: Float

    public init(fast: Bool = false, minimumConfidence: Float = 0.3) {
        self.fast = fast
        self.minimumConfidence = minimumConfidence
    }

    public func recognizeText(in image: CGImage) throws -> [RecognizedTextLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return [] }
        var lines: [RecognizedTextLine] = []

        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first,
                  topCandidate.confidence >= minimumConfidence else { continue }
            let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let box = observation.boundingBox
            let normalizedBox = [Double(box.origin.x), Double(box.origin.y), Double(box.size.width), Double(box.size.height)]
            lines.append(RecognizedTextLine(text: text, confidence: topCandidate.confidence, boundingBox: normalizedBox))
        }

        // Sort lines top-to-bottom (Vision coordinate y=0 is at bottom, so descending y), then left-to-right (ascending x)
        lines.sort { a, b in
            let aY = a.boundingBox.count > 1 ? a.boundingBox[1] : 0
            let bY = b.boundingBox.count > 1 ? b.boundingBox[1] : 0
            if abs(aY - bY) > 0.02 {
                return aY > bY
            }
            let aX = a.boundingBox.count > 0 ? a.boundingBox[0] : 0
            let bX = b.boundingBox.count > 0 ? b.boundingBox[0] : 0
            return aX < bX
        }

        return lines
    }
}

/// Protocol for capturing desktop display frames.
public protocol ScreenFrameProviding: Sendable {
    func captureDisplayImage() async throws -> CGImage?
}

private actor ScreenPermissionGate {
    private var requested = false
    func allowed() async -> Bool {
        if await MainActor.run(body: { CGPreflightScreenCaptureAccess() }) { return true }
        guard !requested else { return false }; requested = true
        return await MainActor.run { CGRequestScreenCaptureAccess() }
    }
}
/// ScreenCaptureKit main-display capture. Images remain transient in memory.
public struct NativeScreenFrameProvider: ScreenFrameProviding {
    private let permission = ScreenPermissionGate()
    public init() {}
    public func captureDisplayImage() async throws -> CGImage? {
        guard await permission.allowed() else {
            throw CapturePrivacyBlocked("Screen Recording permission required; selected OCR resumes when permission is available")
        }
        let privacy = await MainActor.run { (IsSecureEventInputEnabled(), UserDefaults.standard.stringArray(forKey: "Newton.captureExcludedBundleIDs") ?? []) }
        guard !privacy.0 else { throw CapturePrivacyBlocked("Secure input active; main-display OCR paused") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
            throw StoreError(message: "The main display is unavailable for Screen OCR.")
        }
        let configuration = SCStreamConfiguration()
        configuration.width = display.width; configuration.height = display.height
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingApplications: content.applications.filter { privacy.1.contains($0.bundleIdentifier) }, exceptingWindows: []), configuration: configuration)
    }
}

/// Actor-isolated on-device screen capture and OCR engine.
public actor VisionCaptureEngine {
    private let recognizer: any TextRecognizing
    private let frameProvider: any ScreenFrameProviding
    private var captureInFlight = false
    private var lastFrameDigest: Data?
    private var lastRecognitionTime: TimeInterval?
    private let uptime: @Sendable () -> TimeInterval
    public private(set) var skippedDuplicateFramesCount: Int = 0

    public init(
        recognizer: any TextRecognizing = AppleVisionTextRecognizer(),
        frameProvider: any ScreenFrameProviding = NativeScreenFrameProvider(),
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.recognizer = recognizer
        self.frameProvider = frameProvider
        self.uptime = uptime
    }

    /// Fixed-size raster samples the entire display, independent of row stride or pixel format.
    /// Exact digest equality suppresses duplicate sampled images; periodic OCR bounds sampling loss.
    public func computeFrameDigest(for image: CGImage) -> Data? {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return rendered ? Data(SHA256.hash(data: Data(pixels))) : nil
    }
    public func computeFrameHash(for image: CGImage) -> Int {
        (computeFrameDigest(for: image) ?? Data()).prefix(8).reduce(0) { ($0 &* 31) &+ Int($1) }
    }

    /// Captures the current display frame, runs OCR, and returns the recognized frame if text is found.
    /// Uses Frame Hash Deduplication to skip OCR when the screen is static.
    public func captureFrame(appName: String = "", windowTitle: String = "", force: Bool = false) async throws -> RecognizedScreenFrame? {
        guard !captureInFlight else { return nil }
        captureInFlight = true
        defer { captureInFlight = false }
        guard let image = try await frameProvider.captureDisplayImage() else {
            return nil
        }

        try Task.checkCancellation()
        let digest = computeFrameDigest(for: image)
        let now = uptime()
        if !force, let digest, digest == lastFrameDigest,
           let lastRecognitionTime, now - lastRecognitionTime < 60 {
            skippedDuplicateFramesCount += 1
            return nil
        }
        // Failed OCR must be retried; only successful recognition advances suppression state.
        let frame = try recognize(image: image, appName: appName, windowTitle: windowTitle)
        lastFrameDigest = digest; lastRecognitionTime = now
        return frame
    }

    /// Performs text recognition on a provided CGImage.
    public func recognize(image: CGImage, appName: String = "", windowTitle: String = "") throws -> RecognizedScreenFrame {
        let lines = try recognizer.recognizeText(in: image)
        let fullText = lines.map(\.text).joined(separator: "\n")
        return RecognizedScreenFrame(
            appName: appName.isEmpty ? "Active Display" : appName,
            windowTitle: windowTitle,
            fullText: fullText,
            lines: lines
        )
    }
}
