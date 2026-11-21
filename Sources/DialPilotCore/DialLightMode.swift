import Foundation

/// User-selectable light behavior. All On / Off mirror the device's native
/// global modes; Smart follows agent events through the render engine.
public enum DialLightMode: String, CaseIterable, Codable, Sendable {
    case allOn
    case off
    case smart

    public var displayName: String {
        switch self {
        case .allOn: L10n.text(.lightModeAllOn)
        case .off: L10n.text(.lightModeOff)
        case .smart: L10n.text(.lightModeSmart)
        }
    }

    public var hint: String {
        switch self {
        case .allOn: L10n.text(.lightModeAllOnHint)
        case .off: L10n.text(.lightModeOffHint)
        case .smart: L10n.text(.lightModeSmartHint)
        }
    }

    /// The static device table for non-smart modes; nil for smart.
    /// All On uses global mode 1 (lights all four LEDs, including the
    /// firmware-driven voice key — same as the native all-on mode).
    /// Off uses global mode 0 with host LEDs off.
    public var staticTable: DialLedState? {
        switch self {
        case .allOn:
            var table = DialLedState.baseline
            table.mode = 1
            table.allOnBrightness = 15
            return table
        case .off:
            return DialLedPattern.pattern(for: .idle).base
        case .smart:
            return nil
        }
    }
}