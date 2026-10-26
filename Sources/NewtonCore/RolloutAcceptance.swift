import Foundation

public struct RolloutAcceptance: Codable, Sendable {
    public var nativeLaunch: Bool
    public var menuAndShortcuts: Bool
    public var selectedWindow: Bool
    public var keyboardInterception: Bool
    public var meetingTranscription: Bool
    public var mailReadTwice: Bool
    public var disposableCodexJob: Bool
    public var realSleepWakeCycles: Int
    public var binarySHA256: String
    public var soakReceiptPath: String
    public var recordedAt: Date
    public init(nativeLaunch: Bool = false,menuAndShortcuts: Bool = false,selectedWindow: Bool = false,keyboardInterception: Bool = false,meetingTranscription: Bool = false,mailReadTwice: Bool = false,disposableCodexJob: Bool = false,realSleepWakeCycles: Int = 0,binarySHA256: String,soakReceiptPath: String,recordedAt: Date = Date()) {
        self.nativeLaunch = nativeLaunch; self.menuAndShortcuts = menuAndShortcuts; self.selectedWindow = selectedWindow; self.keyboardInterception = keyboardInterception; self.meetingTranscription = meetingTranscription; self.mailReadTwice = mailReadTwice; self.disposableCodexJob = disposableCodexJob; self.realSleepWakeCycles = realSleepWakeCycles; self.binarySHA256 = binarySHA256; self.soakReceiptPath = soakReceiptPath; self.recordedAt = recordedAt
    }
    public func denial(currentBinarySHA256: String) -> String? {
        guard binarySHA256.count == 64,currentBinarySHA256.count == 64,binarySHA256 == currentBinarySHA256 else { return "Acceptance belongs to another binary" }
        let checks = [(nativeLaunch,"native launch"),(menuAndShortcuts,"menu/shortcuts"),(selectedWindow,"selected window"),(keyboardInterception,"keyboard interception"),(meetingTranscription,"meeting transcription"),(mailReadTwice,"repeated Mail intake"),(disposableCodexJob,"disposable Codex job"),(realSleepWakeCycles >= 2,"two real sleep/wake cycles")]
        let missing = checks.filter { !$0.0 }.map(\.1)
        guard missing.isEmpty else { return "Acceptance pending: " + missing.joined(separator: ", ") }
        struct Soak: Decodable {
            let complete: Bool
            let requestedSeconds: Double
            let elapsedSeconds: Double
            let binarySHA256: String
            let errors: [String]
        }
        let url = URL(fileURLWithPath: soakReceiptPath)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,size <= 20_000_000,
              let data = try? Data(contentsOf: url),let soak = try? JSONDecoder().decode(Soak.self,from: data),
              soak.complete,soak.requestedSeconds >= 86400,soak.elapsedSeconds >= soak.requestedSeconds,soak.errors.isEmpty,soak.binarySHA256 == binarySHA256 else { return "Matching 24-hour soak not yet complete" }
        return nil
    }
    public static func read(from url: URL,currentBinarySHA256: String) -> String? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,size <= 100_000,
              let data = try? Data(contentsOf: url),let receipt = try? JSONDecoder().decode(Self.self,from: data) else { return "Rollout acceptance receipt unavailable" }
        return receipt.denial(currentBinarySHA256: currentBinarySHA256)
    }
}
