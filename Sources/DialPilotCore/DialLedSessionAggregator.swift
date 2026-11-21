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
        /// Which agent owns this session (raw DialAgentTarget value or a
        /// free-form source like "qwenwork"). nil for legacy/manual events.
        public var agent: String?

        public init(state: DialAgentState, lastSeen: TimeInterval, agent: String? = nil) {
            self.state = state
            self.lastSeen = lastSeen
            self.agent = agent
        }
    }

    /// One active session as shown in the panel / ctl status detail.
    public struct SessionInfo: Equatable, Sendable {
        public let id: String
        public let agent: String?
        public let state: DialAgentState
        public let ageSeconds: TimeInterval
        /// True when this session's state is the one on the device LEDs.
        public let isWinning: Bool
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
        now: TimeInterval,
        agent: String? = nil
    ) -> DialAgentState {
        var entry = Session(state: state, lastSeen: now, agent: agent)
        // Keep the first-known agent if a later event omits it.
        if agent == nil { entry.agent = sessions[session]?.agent }
        sessions[session] = entry
        return resolvedState(now: now)
    }

    /// Drops stale sessions and returns the resolved state.
    public mutating func prune(now: TimeInterval) -> DialAgentState {
        sessions = sessions.filter { now - $0.value.lastSeen < staleInterval }
        return resolvedState(now: now)
    }

    public func resolvedState(now: TimeInterval) -> DialAgentState {
        winningSession(now: now)?.session.state ?? .idle
    }

    /// The session whose state is currently on the LEDs: highest priority
    /// among non-stale sessions; ties break on most-recent event, then on
    /// session id so the choice is deterministic.
    public func winningSession(now: TimeInterval) -> (id: String, session: Session)? {
        let active = sessions.filter { now - $0.value.lastSeen < staleInterval }
        return active.max { a, b in
            if a.value.state.priority != b.value.state.priority {
                return a.value.state.priority < b.value.state.priority
            }
            if a.value.lastSeen != b.value.lastSeen {
                return a.value.lastSeen < b.value.lastSeen
            }
            return a.key > b.key
        }.map { (id: $0.key, session: $0.value) }
    }

    /// All non-stale sessions, winning one first, then by priority.
    /// This is the "who else is running" detail behind the single LED state.
    public func activeSessions(now: TimeInterval) -> [SessionInfo] {
        let winnerID = winningSession(now: now)?.id
        return sessions
            .filter { now - $0.value.lastSeen < staleInterval }
            .map { id, session in
                SessionInfo(
                    id: id,
                    agent: session.agent,
                    state: session.state,
                    ageSeconds: max(0, now - session.lastSeen),
                    isWinning: id == winnerID
                )
            }
            .sorted { a, b in
                if a.isWinning != b.isWinning { return a.isWinning }
                if a.state.priority != b.state.priority { return a.state.priority > b.state.priority }
                return a.ageSeconds < b.ageSeconds
            }
    }

    public var activeSessionCount: Int { sessions.count }
}