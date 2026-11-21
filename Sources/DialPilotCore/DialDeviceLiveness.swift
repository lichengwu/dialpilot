import Foundation

/// Decides whether the AU05 is actually *answering*, not merely plugged in.
///
/// The device keeps its USB interface alive when the knob itself is switched
/// off: `IOHIDDeviceSetReport` still returns `kIOReturnSuccess`, no removal
/// callback fires, and the menu bar happily claims "gestures active" while
/// nothing can reach the knob (user report 2026-11-21, powered-off AU05 still
/// shown as connected with a stale battery percentage).
///
/// The only honest liveness signal the protocol gives us is the power query
/// round trip: the firmware answers every GET it receives while awake. So we
/// count *polls that produced no reply at all*; a live device resets the
/// counter within milliseconds of each poll.
///
/// Deliberately count-based rather than time-based: a poll is sent only every
/// N heartbeats, so "two polls in a row unanswered" already spans several
/// seconds, and no extra timer is needed to express it.
public struct DialDeviceLiveness: Equatable, Sendable {
    /// Two silent polls in a row. One is not enough — a single dropped report
    /// during a USB hiccup must not flip the UI to "not responding".
    public static let silentPollsBeforeUnresponsive = 2

    /// True while the device answers. Starts optimistic: a freshly attached
    /// device is assumed alive until proven silent.
    public private(set) var isResponsive = true

    /// Polls sent since the last reply. Reset by any *proof of life*: a power
    /// reply or a real gesture. USB-level ACKs do not count — the interface
    /// chip keeps answering after the knob's own firmware is off.
    public private(set) var silentPolls = 0

    public init() {}

    /// A poll (one batch of GETs) was just handed to the device.
    public mutating func pollSent() {
        silentPolls += 1
        if silentPolls >= Self.silentPollsBeforeUnresponsive {
            isResponsive = false
        }
    }

    /// A reply that only the device firmware could have produced — a power
    /// query answer, or a gesture. Callers must not pass USB-shell ACKs.
    public mutating func replyReceived() {
        silentPolls = 0
        isResponsive = true
    }

    /// Device attach/detach: forget the past, trust the new state.
    public mutating func reset() {
        silentPolls = 0
        isResponsive = true
    }

    /// While unresponsive, poll far more often so the UI recovers within a few
    /// seconds of the knob being switched back on. Capped at 8 heartbeats
    /// (~6.4 s) so the extra traffic stays trivial.
    public func pollInterval(whileAlive desired: UInt64) -> UInt64 {
        guard !isResponsive, desired > 8 else { return desired }
        return 8
    }
}
