import AppKit
import Foundation
import CoreAudio
import NewtonCore

/// Native color sampler utility using Apple NSColorSampler.
@MainActor
public final class ColorSampler: ObservableObject {
    public static let shared = ColorSampler()
    private var activeSampler: NSColorSampler?

    public init() {}

    /// Opens the native macOS eyedropper loupe and copies the selected hex color to the pasteboard.
    public func sampleColor() async -> String? {
        guard activeSampler == nil else { return nil }
        let sampler = NSColorSampler()
        activeSampler = sampler

        return await withCheckedContinuation { continuation in
            sampler.show { [weak self] color in
                Task { @MainActor [weak self] in
                    self?.activeSampler = nil
                    guard let color, let srgb = color.usingColorSpace(.sRGB) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    let r = Int(round(srgb.redComponent * 255))
                    let g = Int(round(srgb.greenComponent * 255))
                    let b = Int(round(srgb.blueComponent * 255))
                    let hex = String(format: "#%02X%02X%02X", r, g, b)

                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(hex, forType: .string)

                    continuation.resume(returning: hex)
                }
            }
        }
    }
}

/// Global system microphone mute controller via CoreAudio.
@MainActor
public final class MicMuteController: ObservableObject {
    public static let shared = MicMuteController()
    @Published public private(set) var isMuted = false

    public init() {
        self.isMuted = queryDefaultInputMute()
    }

    /// Toggles the system default input microphone mute state.
    @discardableResult
    public func toggleMute() -> Bool {
        let newState = !isMuted
        if setMuteState(newState) {
            isMuted = newState
        }
        return isMuted
    }

    private func defaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioDeviceUnknown else { return nil }
        return deviceID
    }

    private func queryDefaultInputMute() -> Bool {
        guard let deviceID = defaultInputDeviceID() else { return false }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return false }
        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &muted)
        return status == noErr && muted != 0
    }

    private func setMuteState(_ mute: Bool) -> Bool {
        guard let deviceID = defaultInputDeviceID() else { return false }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &propertyAddress) else { return false }
        var muted: UInt32 = mute ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, dataSize, &muted)
        return status == noErr
    }
}
