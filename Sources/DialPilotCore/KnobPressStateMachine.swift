import Foundation

public enum KnobPressDecision: Equatable, Sendable {
    case scheduleSinglePress(after: TimeInterval)
    case cancelPendingSinglePress
    case performSinglePress
    case performDoublePress
}

/// Distinguishes one click from two clicks without ever firing the
/// single-click action before the double-click window has closed.
///
/// The 0.65 s long-press gesture is gone. It existed
/// only to switch between the AI and System profiles; with a single
/// profile there is nothing to switch to, so the hold timer and its
/// two decisions (`longPressRecognized` / `switchProfile`) were removed
/// rather than left as dead paths.
public struct KnobPressStateMachine: Equatable, Sendable {
    public let doublePressInterval: TimeInterval

    private var pressedAt: TimeInterval?
    private var firstReleasedAt: TimeInterval?
    private var isSecondPress = false

    public init(doublePressInterval: TimeInterval = 0.28) {
        self.doublePressInterval = doublePressInterval
    }

    public mutating func pressDown(at timestamp: TimeInterval) -> [KnobPressDecision] {
        guard pressedAt == nil else { return [] }

        var decisions: [KnobPressDecision] = []
        if let firstReleasedAt,
           timestamp - firstReleasedAt <= doublePressInterval + 1e-9 {
            isSecondPress = true
            decisions.append(.cancelPendingSinglePress)
        } else {
            if firstReleasedAt != nil {
                decisions.append(.cancelPendingSinglePress)
                decisions.append(.performSinglePress)
            }
            self.firstReleasedAt = nil
            isSecondPress = false
        }

        pressedAt = timestamp
        return decisions
    }

    public mutating func pressUp(at timestamp: TimeInterval) -> [KnobPressDecision] {
        // A release without a matching press is noise (or a re-sent report
        // after reconnect) and must not arm the single-press timer.
        guard pressedAt != nil else { return [] }
        self.pressedAt = nil

        if isSecondPress {
            clearClickCycle()
            return [.cancelPendingSinglePress, .performDoublePress]
        }

        firstReleasedAt = timestamp
        return [.scheduleSinglePress(after: doublePressInterval)]
    }

    public mutating func singlePressTimerFired() -> KnobPressDecision? {
        guard pressedAt == nil, firstReleasedAt != nil else { return nil }
        clearClickCycle()
        return .performSinglePress
    }

    public mutating func reset() {
        pressedAt = nil
        clearClickCycle()
    }

    private mutating func clearClickCycle() {
        firstReleasedAt = nil
        isSecondPress = false
    }
}
