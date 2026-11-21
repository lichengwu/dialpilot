import XCTest
@testable import DialPilotCore

final class DialLedSessionAggregatorTests: XCTestCase {
    func testHighestPriorityWins() {
        var aggregator = DialLedSessionAggregator()
        _ = aggregator.record(session: "a", state: .working, now: 100)
        XCTAssertEqual(aggregator.record(session: "b", state: .thinking, now: 101), .thinking)
        XCTAssertEqual(aggregator.record(session: "c", state: .notification, now: 102), .notification)
        // Working session updates must not dethrone notification.
        XCTAssertEqual(aggregator.record(session: "a", state: .working, now: 103), .notification)
    }

    func testStaleSessionsAreDropped() {
        var aggregator = DialLedSessionAggregator(staleInterval: 120)
        _ = aggregator.record(session: "a", state: .notification, now: 100)
        _ = aggregator.record(session: "b", state: .working, now: 200)
        // At 221 the notification session is stale (>120s), working wins.
        XCTAssertEqual(aggregator.prune(now: 221), .working)
        XCTAssertEqual(aggregator.activeSessionCount, 1)
    }

    func testEmptyResolvesToIdle() {
        var aggregator = DialLedSessionAggregator()
        XCTAssertEqual(aggregator.resolvedState(now: 0), .idle)
        _ = aggregator.record(session: "a", state: .working, now: 0)
        XCTAssertEqual(aggregator.prune(now: 1000), .idle)
    }

    func testErrorBeatsWorkingButLosesToNotification() {
        var aggregator = DialLedSessionAggregator()
        _ = aggregator.record(session: "a", state: .error, now: 0)
        XCTAssertEqual(aggregator.record(session: "b", state: .working, now: 1), .error)
        XCTAssertEqual(aggregator.record(session: "c", state: .notification, now: 2), .notification)
    }

    func testStaleBoundaryIsExclusive() {
        var aggregator = DialLedSessionAggregator(staleInterval: 120)
        _ = aggregator.record(session: "a", state: .working, now: 0)
        // Exactly at the interval the session is stale (strict <).
        XCTAssertEqual(aggregator.resolvedState(now: 120), .idle)
        XCTAssertEqual(aggregator.resolvedState(now: 119.9), .working)
    }

    func testSameSessionUpdateReplacesState() {
        var aggregator = DialLedSessionAggregator()
        _ = aggregator.record(session: "a", state: .notification, now: 0)
        XCTAssertEqual(aggregator.record(session: "a", state: .idle, now: 1), .idle)
        XCTAssertEqual(aggregator.activeSessionCount, 1)
    }

    func testSweepingBeatsThinkingAndWorking() {
        var aggregator = DialLedSessionAggregator()
        _ = aggregator.record(session: "a", state: .thinking, now: 0)
        _ = aggregator.record(session: "b", state: .working, now: 0)
        XCTAssertEqual(aggregator.record(session: "c", state: .sweeping, now: 1), .sweeping)
    }

    func testAttentionBeatsIdleButLosesToWorking() {
        var aggregator = DialLedSessionAggregator()
        _ = aggregator.record(session: "a", state: .attention, now: 0)
        XCTAssertEqual(aggregator.record(session: "b", state: .idle, now: 1), .attention)
        XCTAssertEqual(aggregator.record(session: "c", state: .working, now: 2), .working)
    }

    func testPruneRemovesOnlyStaleAndKeepsFreshWinner() {
        var aggregator = DialLedSessionAggregator(staleInterval: 120)
        _ = aggregator.record(session: "old", state: .notification, now: 0)
        _ = aggregator.record(session: "fresh", state: .thinking, now: 100)
        XCTAssertEqual(aggregator.prune(now: 150), .thinking)
        XCTAssertEqual(aggregator.activeSessionCount, 1)
    }

    func testResolvedStateDoesNotMutateSessions() {
        var aggregator = DialLedSessionAggregator(staleInterval: 120)
        _ = aggregator.record(session: "a", state: .working, now: 0)
        _ = aggregator.resolvedState(now: 500) // stale but not pruned
        XCTAssertEqual(aggregator.activeSessionCount, 1,
                       "resolvedState must be a read-only view")
        XCTAssertEqual(aggregator.prune(now: 500), .idle)
    }
}

final class DialCodexAndDshInstallerTests: XCTestCase {
    func testCodexFeaturesAddedWhenAbsent() {
        let updated = DialHookInstaller.codexConfigEnablingHooks(existing: "model = \"gpt-5\"\n")
        XCTAssertNotNil(updated)
        XCTAssertTrue(updated!.contains("[features]"))
        XCTAssertTrue(updated!.contains("hooks = true"))
        XCTAssertTrue(updated!.contains("model = \"gpt-5\""))
    }

    func testCodexFeaturesIdempotent() {
        let existing = "[features]\nhooks = true\n"
        XCTAssertNil(DialHookInstaller.codexConfigEnablingHooks(existing: existing))
    }

    func testCodexFeaturesFalseFlipped() {
        let existing = "[features]\nhooks = false\n"
        let updated = DialHookInstaller.codexConfigEnablingHooks(existing: existing)
        XCTAssertEqual(updated, "[features]\nhooks = true\n")
    }

    func testCodexFeaturesInsertedIntoExistingSection() {
        let existing = "[features]\nother = 1\n\n[other]\nx = 2\n"
        let updated = DialHookInstaller.codexConfigEnablingHooks(existing: existing)!
        XCTAssertTrue(updated.contains("[features]\nhooks = true\nother = 1"))
        XCTAssertTrue(updated.contains("[other]"))
    }

    func testDshMergeIntoEmpty() {
        let merged = DialHookInstaller.mergedDshPatch(existing: nil, ctlPath: "/bin/ctl")
        XCTAssertTrue(merged.contains("- id: dialpilot-led"))
        XCTAssertTrue(merged.contains("approval/asked"))
        XCTAssertTrue(merged.contains("--dialect dsh"))
    }

    func testDshMergePreservesOtherItems() {
        let existing = "- id: other-plugin\n  config:\n    foo: bar\n"
        let merged = DialHookInstaller.mergedDshPatch(existing: existing, ctlPath: "/bin/ctl")
        XCTAssertTrue(merged.contains("- id: other-plugin"))
        XCTAssertTrue(merged.contains("foo: bar"))
        XCTAssertTrue(merged.contains("- id: dialpilot-led"))
    }

    func testDshReinstallReplacesMarkedBlockOnly() {
        let first = DialHookInstaller.mergedDshPatch(
            existing: "- id: other-plugin\n  config:\n    foo: bar\n", ctlPath: "/bin/ctl"
        )
        let second = DialHookInstaller.mergedDshPatch(existing: first, ctlPath: "/bin/ctl2")
        XCTAssertEqual(
            second.components(separatedBy: "- id: dialpilot-led").count - 1, 1,
            "marked block must appear exactly once"
        )
        XCTAssertTrue(second.contains("/bin/ctl2"))
        XCTAssertTrue(second.contains("- id: other-plugin"))
    }

    func testDshUninstallRemovesOnlyMarkedBlock() {
        let merged = DialHookInstaller.mergedDshPatch(
            existing: "- id: other-plugin\n  config:\n    foo: bar\n", ctlPath: "/bin/ctl"
        )
        let unmerged = DialHookInstaller.unmergedDshPatch(existing: merged)
        XCTAssertNotNil(unmerged)
        XCTAssertFalse(unmerged!.contains("dialpilot-led"))
        XCTAssertTrue(unmerged!.contains("- id: other-plugin"))
        XCTAssertTrue(unmerged!.contains("foo: bar"))
    }

    func testDshUninstallWithoutMarkerReturnsNil() {
        XCTAssertNil(DialHookInstaller.unmergedDshPatch(existing: "- id: other\n"))
    }

    func testCodexUsesClaudeJSONContract() throws {
        XCTAssertTrue(DialAgentTarget.codex.usesClaudeJSONContract)
        XCTAssertEqual(DialAgentTarget.codex.settingsRelativePath, ".codex/hooks.json")
        let data = try DialHookInstaller.mergedSettings(
            existing: nil, target: .codex, ctlPath: "/bin/ctl"
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(DialHookInstaller.containsMarker(in: root))
    }
}
/// Session visibility: winner identity, agent attribution, detail list.
final class DialLedSessionVisibilityTests: XCTestCase {
    func testWinningSessionCarriesAgentAndID() {
        var agg = DialLedSessionAggregator()
        _ = agg.record(session: "s1", state: .working, now: 100, agent: "codebuddy")
        _ = agg.record(session: "s2", state: .notification, now: 101, agent: "claude-code")
        let winner = agg.winningSession(now: 102)
        XCTAssertEqual(winner?.id, "s2")
        XCTAssertEqual(winner?.session.agent, "claude-code")
        XCTAssertEqual(winner?.session.state, .notification)
    }

    func testAgentSurvivesEventWithoutAgent() {
        var agg = DialLedSessionAggregator()
        _ = agg.record(session: "s1", state: .working, now: 100, agent: "qoder")
        _ = agg.record(session: "s1", state: .thinking, now: 101)
        XCTAssertEqual(agg.sessions["s1"]?.agent, "qoder")
    }

    func testActiveSessionsWinnerFirstThenPriority() {
        var agg = DialLedSessionAggregator()
        _ = agg.record(session: "idle-one", state: .idle, now: 100, agent: "codex")
        _ = agg.record(session: "worker", state: .working, now: 101, agent: "codebuddy")
        _ = agg.record(session: "approver", state: .notification, now: 102, agent: "claude-code")
        let list = agg.activeSessions(now: 103)
        XCTAssertEqual(list.map(\.id), ["approver", "worker", "idle-one"])
        XCTAssertEqual(list.filter(\.isWinning).count, 1)
        XCTAssertEqual(list.first?.ageSeconds, 1)
    }

    func testStaleSessionsExcludedFromDetail() {
        var agg = DialLedSessionAggregator(staleInterval: 120)
        _ = agg.record(session: "old", state: .error, now: 0, agent: "dsh")
        _ = agg.record(session: "new", state: .working, now: 200, agent: "codebuddy")
        let list = agg.activeSessions(now: 201)
        XCTAssertEqual(list.map(\.id), ["new"])
        XCTAssertEqual(agg.resolvedState(now: 201), .working)
    }

    func testTieBreaksOnMostRecentThenID() {
        var agg = DialLedSessionAggregator()
        _ = agg.record(session: "a", state: .working, now: 100)
        _ = agg.record(session: "b", state: .working, now: 105)
        XCTAssertEqual(agg.winningSession(now: 106)?.id, "b")
        _ = agg.record(session: "a", state: .working, now: 105)
        // Same priority, same lastSeen: deterministic — smaller id wins.
        XCTAssertEqual(agg.winningSession(now: 106)?.id, "a")
    }

    func testEmptyAggregatorHasNoWinner() {
        let agg = DialLedSessionAggregator()
        XCTAssertNil(agg.winningSession(now: 100))
        XCTAssertTrue(agg.activeSessions(now: 100).isEmpty)
        XCTAssertEqual(agg.resolvedState(now: 100), .idle)
    }
}
