import Foundation

/// Pure decision logic for the Ulanzi Studio ↔ DialPilot handover.
///
/// Two hosts cannot drive the AU05 at once, so DialPilot stands down while
/// Studio runs. Getting *back* used to rely solely on
/// `NSWorkspace.didTerminateApplicationNotification` — and on 2026-11-23 a
/// real SIGTERM of Studio produced no resume at all (no log line, listener
/// stayed down until the app was restarted). Notifications are a fast path,
/// not a guarantee; this tracker turns every UI refresh into a cheap
/// state-diff so recovery also happens by observation.
public struct DialVendorPresence {
    /// Last observed presence of the vendor app; nil until first observation.
    private var lastSeenRunning: Bool?

    public init() {}

    public enum Transition: Equatable {
        /// First observation, or no change — nothing to do.
        case unchanged
        /// Vendor just appeared: stand down.
        case appeared
        /// Vendor just exited: try to take the device back.
        case exited
    }

    /// Feed the current presence; returns what changed since last time.
    public mutating func observe(running: Bool) -> Transition {
        defer { lastSeenRunning = running }
        guard let previous = lastSeenRunning else { return .unchanged }
        if previous == running { return .unchanged }
        return running ? .appeared : .exited
    }
}
