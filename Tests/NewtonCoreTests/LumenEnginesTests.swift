import Testing
import Foundation
import IOKit.ps
@testable import NewtonCore

struct LumenEnginesTests {
    @Test func missingBatteryNeverInventsPowerRunwayOrChargeState() {
        let snapshot = PowerPacingEngine.snapshot(source: nil, cycleCount: nil, thermal: "Fair")
        #expect(snapshot.batteryLevel == nil)
        #expect(snapshot.isCharging == nil && snapshot.isPluggedIn == nil)
        #expect(snapshot.estimatedRemainingMinutes == nil && snapshot.estimatedWatts == nil && snapshot.cycleCount == nil)
        #expect(snapshot.thermalState == "Fair")
        #expect(snapshot.runwayFormatted == "Battery runway unavailable")
        #expect(snapshot.narrative.contains("unavailable"))
    }
    @Test func supportedBatteryFieldsAndInvalidEstimatesAreExplicit() {
        let source: [String: Any] = [kIOPSCurrentCapacityKey: 75, kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSTimeToEmptyKey: -1]
        let snapshot = PowerPacingEngine.snapshot(source: source, cycleCount: 0, thermal: "Nominal")
        #expect(snapshot.batteryPercent == 75)
        #expect(snapshot.runwayFormatted == "Charging (75%)")
        #expect(snapshot.estimatedWatts == nil && snapshot.estimatedRemainingMinutes == nil)
        #expect(snapshot.cycleCount == 0)
        let battery = PowerSnapshot(batteryLevel: 0.5, isCharging: false, isPluggedIn: false, estimatedRemainingMinutes: 185)
        #expect(battery.runwayFormatted == "3h 5m remaining")
        #expect(PowerSnapshot.empty.batteryLevel == nil)
    }
}
