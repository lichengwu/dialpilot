import XCTest
@testable import DialPilotCore

/// Pins the approved menu-bar badge design (2026-11-21): exceptions only,
/// one slot, fixed priority, device-reported low-battery hint honored.
final class DialStatusBarTests: XCTestCase {
    private func battery(
        percent: UInt16,
        charging: Bool = false,
        full: Bool = false,
        lowLevel: UInt8 = 0
    ) -> DialBatteryStatus {
        DialBatteryStatus(
            percent: percent, voltageMillivolts: 4000,
            isCharging: charging, isFullyCharged: full,
            lowBatteryLevel: lowLevel, isPoweredOff: false
        )
    }

    private func resolve(
        connected: Bool = true, ax: Bool = true, im: Bool = true,
        battery: DialBatteryStatus? = nil, responsive: Bool = true
    ) -> DialStatusBarState {
        DialStatusBar.resolve(
            deviceConnected: connected,
            deviceResponsive: responsive,
            accessibilityGranted: ax,
            inputMonitoringGranted: im,
            battery: battery
        )
    }

    func testHealthySetupShowsNoBadge() {
        XCTAssertEqual(resolve(battery: battery(percent: 80)), .normal)
        XCTAssertEqual(resolve(battery: nil), .normal)
    }

    func testDisconnectedWinsOverEverything() {
        XCTAssertEqual(
            resolve(connected: false, ax: false, battery: battery(percent: 5, lowLevel: 2)),
            .disconnected
        )
    }

    /// A powered-off AU05 keeps its USB interface enumerated. Showing the
    /// healthy glyph there is a lie the user caught on 2026-11-21.
    func testSilentDeviceRendersAsDisconnected() {
        XCTAssertEqual(resolve(battery: battery(percent: 50), responsive: false), .disconnected)
        XCTAssertEqual(
            resolve(connected: false, ax: false, responsive: false),
            .disconnected
        )
    }

    func testPermissionBeatsBattery() {
        XCTAssertEqual(resolve(ax: false, battery: battery(percent: 5)), .needsPermission)
        XCTAssertEqual(resolve(im: false, battery: battery(percent: 5)), .needsPermission)
    }

    func testLowBatteryBelowFallbackThreshold() {
        XCTAssertEqual(resolve(battery: battery(percent: 19)), .lowBattery)
        XCTAssertEqual(resolve(battery: battery(percent: 20)), .normal)
    }

    func testDeviceLowLevelHintBeatsPercent() {
        // Device says "I'm low" (level 2) even at 45% — trust the device.
        XCTAssertEqual(resolve(battery: battery(percent: 45, lowLevel: 2)), .lowBattery)
    }

    func testChargingSuppressesLowBadge() {
        XCTAssertEqual(resolve(battery: battery(percent: 5, charging: true)), .charging)
        XCTAssertEqual(resolve(battery: battery(percent: 5, charging: true, lowLevel: 3)), .charging)
    }

    func testFullyChargedShowsNoBadge() {
        XCTAssertEqual(resolve(battery: battery(percent: 100, charging: true, full: true)), .normal)
    }

    func testNoBatteryReadingIsNotLow() {
        // Unknown battery must not fake a red dot.
        XCTAssertEqual(resolve(battery: nil), .normal)
    }
}