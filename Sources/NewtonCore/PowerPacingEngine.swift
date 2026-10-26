import Foundation
import IOKit.ps

public struct PowerSnapshot: Sendable, Codable, Equatable {
    public let batteryLevel: Double?
    public let isCharging: Bool?
    public let isPluggedIn: Bool?
    public let estimatedRemainingMinutes: Int?
    public let estimatedWatts: Double?
    public var packageWatts: Double? { nil }
    public var wattsSource: String { "Battery discharge estimate · SmartBattery current × voltage" }
    public let cycleCount: Int?
    public let thermalState: String
    public let diagnostics: [String]
    public let timestamp: Date
    public var narrative: String { diagnostics.joined(separator: " · ") }
    public init(batteryLevel: Double? = nil, isCharging: Bool? = nil, isPluggedIn: Bool? = nil,
                estimatedRemainingMinutes: Int? = nil, estimatedWatts: Double? = nil, cycleCount: Int? = nil,
                thermalState: String = "Unavailable", diagnostics: [String] = [], timestamp: Date = Date()) {
        self.batteryLevel = batteryLevel; self.isCharging = isCharging; self.isPluggedIn = isPluggedIn
        self.estimatedRemainingMinutes = estimatedRemainingMinutes; self.estimatedWatts = estimatedWatts
        self.cycleCount = cycleCount; self.thermalState = thermalState; self.diagnostics = diagnostics
        self.timestamp = timestamp
    }
    public static let empty = PowerSnapshot(diagnostics: ["Battery information unavailable", "SoC watts unavailable in this release"])
    public var batteryPercent: Int? { batteryLevel.map { Int($0 * 100) } }
    public var runwayFormatted: String {
        if isCharging == true { return batteryPercent.map { "Charging (\($0)%)" } ?? "Charging" }
        if isPluggedIn == true { return "Power Adapter Connected" }
        guard let minutes = estimatedRemainingMinutes else { return "Battery runway unavailable" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m remaining" : "\(minutes)m remaining"
    }
}
public enum PowerPacingEngine {
    public static func snapshot(source: [String: Any]?, cycleCount: Int?, thermal: String, estimatedWatts: Double? = nil) -> PowerSnapshot {
        var level: Double?
        if let current = source?[kIOPSCurrentCapacityKey] as? Int,
           let maximum = source?[kIOPSMaxCapacityKey] as? Int, maximum > 0, current >= 0, current <= maximum {
            level = Double(current) / Double(maximum)
        }
        let state = source?[kIOPSPowerSourceStateKey] as? String
        let plugged: Bool? = state == kIOPSACPowerValue ? true : (state == kIOPSBatteryPowerValue ? false : nil)
        let remaining = source?[kIOPSTimeToEmptyKey] as? Int
        var diagnostics: [String] = []
        if estimatedWatts == nil { diagnostics.append("SoC watts unavailable in this release") }
        if level == nil { diagnostics.append("Battery level unavailable") }
        if source == nil { diagnostics.append("No supported battery information") }
        if cycleCount == nil { diagnostics.append("Battery cycles unavailable") }
        return PowerSnapshot(batteryLevel: level, isCharging: source?[kIOPSIsChargingKey] as? Bool,
            isPluggedIn: plugged, estimatedRemainingMinutes: remaining.flatMap { $0 > 0 ? $0 : nil },
            estimatedWatts: estimatedWatts, cycleCount: cycleCount, thermalState: thermal, diagnostics: diagnostics)
    }
    public static func captureSnapshot() -> PowerSnapshot {
        var source: [String: Any]?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for item in list {
                if let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                   description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                    source = description; break
                }
            }
        }
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Nominal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Elevated"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unavailable"
        }
        var cycles: Int?
        var watts: Double?
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            cycles = IORegistryEntryCreateCFProperty(service, "CycleCount" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
            if source?[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
               let amp = IORegistryEntryCreateCFProperty(service, "Amperage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
               let volt = IORegistryEntryCreateCFProperty(service, "Voltage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int, volt > 0, amp < 0 {
                watts = abs(Double(amp) * Double(volt)) / 1_000_000.0
            }
            IOObjectRelease(service)
        }
        return snapshot(source: source, cycleCount: cycles, thermal: thermal, estimatedWatts: watts)
    }
}
