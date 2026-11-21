import Foundation

/// Multi-session arbitration.
/// Pure logic: the app feeds events with timestamps; the aggregator decides
/// which single state the renderer should show.
///
/// Priority: notification > error > sweeping > thinking > working >
/// attention > idle/sleeping. Sessions silent for `staleInterval` are
/// dropped (mirrors the official stale-session cleanup).
///
/// OBSERVED BEHAVIOR, NOT A BUG: while a real agent session runs tools it
/// keeps emitting Notification/working events. A manual `led --state X`
/// test during that time gets overridden by the higher-priority live state
/// (e.g. middle+bottom fast blink pressing down a simulated thinking).
/// For clean manual tests, uninstall hooks first; reinstall afterwards.
public struct DialLedSessionAggregator: Equatable, Sendable {
    public struct Session: Equatable, Sendable {
        public var state: DialAgentState
        public var lastSeen: TimeInterval

        public init(state: DialAgentState, lastSeen: TimeInterval) {
            self.state = state
            self.lastSeen = lastSeen
        }
    }

    public private(set) var sessions: [String: Session] = [:]
    public let staleInterval: TimeInterval

    public init(staleInterval: TimeInterval = 120) {
        self.staleInterval = staleInterval
    }

    /// Records an event and returns the state that should now be rendered.
    public mutating func record(
        session: String,
        state: DialAgentState,
        now: TimeInterval
    ) -> DialAgentState {
        sessions[session] = Session(state: state, lastSeen: now)
        return resolvedState(now: now)
    }

    /// Drops stale sessions and returns the resolved state.
    public mutating func prune(now: TimeInterval) -> DialAgentState {
        sessions = sessions.filter { now - $0.value.lastSeen < staleInterval }
        return resolvedState(now: now)
    }

    public func resolvedState(now: TimeInterval) -> DialAgentState {
        let active = sessions.values.filter { now - $0.lastSeen < staleInterval }
        guard let winner = active.max(by: { $0.state.priority < $1.state.priority }) else {
            return .idle
        }
        return winner.state
    }

    public var activeSessionCount: Int { sessions.count }
}