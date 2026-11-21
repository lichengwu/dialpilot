import Foundation

/// What the menu-bar icon should show. One slot, one state — priority
/// decides when several conditions hold at once.
///
/// Design rule (approved 2026-11-21): **the menu bar only reports
/// exceptions**. A healthy setup shows the bare device glyph. Agent
/// activity already has a display (the device LEDs), and the panel
/// already carries a permanent battery dot — a third copy in the menu
/// bar would be noise.
public enum DialStatusBarState: Equatable, Sendable {
    /// Device absent or powered off: faded glyph, dashed body.
    case disconnected
    /// A permission is missing: gestures/lights are stuck. Orange dot.
    case needsPermission
    /// Battery below the low threshold and not charging. Red dot.
    case lowBattery
    /// Plugged in and charging. Green dot; disappears when full.
    case charging
    /// Everything ready: no badge at all.
    case normal
}

public enum DialStatusBar {
    /// Fallback low-battery threshold when the device gives no usable hint.
    public static let fallbackLowThreshold: UInt16 = 20

    /// Resolves the single badge state from live runtime values.
    ///
    /// Priority: disconnected > needsPermission > lowBattery > charging > normal.
    /// Disconnected wins because nothing else matters when the device is
    /// gone; permission next because it silently breaks gestures even on
    /// a connected device.
    ///
    /// Low-battery threshold: the AU05 reports its own `lowBatteryLevel`
    /// (0–3). When non-zero we treat it as "the device itself says low"
    /// and show red regardless of percent — the device's own judgment
    /// beats a guessed number. When it is 0 (or no battery reading
    /// exists) we fall back to percent < 20.
    public static func resolve(
        deviceConnected: Bool,
        deviceResponsive: Bool = true,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        battery: DialBatteryStatus?
    ) -> DialStatusBarState {
        // A powered-off AU05 keeps its USB interface enumerated; treating
        // that as "connected" turns the badge into a lie, so silence is
        // rendered exactly like absence.
        guard deviceConnected, deviceResponsive else { return .disconnected }
        guard accessibilityGranted, inputMonitoringGranted else { return .needsPermission }
        if let battery, !battery.isCharging, !battery.isFullyCharged {
            if battery.lowBatteryLevel > 0 || battery.percent < fallbackLowThreshold {
                return .lowBattery
            }
        }
        if let battery, battery.isCharging, !battery.isFullyCharged {
            return .charging
        }
        return .normal
    }
}