import XCTest
@testable import DialPilotCore

final class DialHookInstallerTests: XCTestCase {
    private let ctl = "/Applications/DialPilot.app/Contents/MacOS/dialpilotctl"

    private func parse(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testMergeIntoEmptyCreatesAllEvents() throws {
        let data = try DialHookInstaller.mergedSettings(
            existing: nil, target: .qoder, ctlPath: ctl
        )
        let root = try parse(data)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        for event in DialAgentTarget.claudeEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]], event)
            XCTAssertEqual(groups.count, 1, event)
            let entries = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
            XCTAssertEqual(entries[0]["name"] as? String, "dialpilot")
            let command = try XCTUnwrap(entries[0]["command"] as? String)
            XCTAssertTrue(command.contains("--agent qoder"))
            XCTAssertTrue(command.contains("--event \(event)"))
        }
        XCTAssertTrue(DialHookInstaller.containsMarker(in: root))
    }

    func testMergePreservesExistingHooks() throws {
        let existing: [String: Any] = [
            "someOtherSetting": true,
            "hooks": [
                "PreToolUse": [
                    [
                        "matcher": "Bash",
                        "hooks": [["type": "command", "name": "user-own", "command": "/bin/echo hi"]],
                    ],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing)
        let merged = try DialHookInstaller.mergedSettings(
            existing: existingData, target: .claudeCode, ctlPath: ctl
        )
        let root = try parse(merged)
        XCTAssertEqual(root["someOtherSetting"] as? Bool, true)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["PreToolUse"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 2)
        let userGroup = groups.first { ($0["matcher"] as? String) == "Bash" }
        let userEntries = try XCTUnwrap(userGroup?["hooks"] as? [[String: Any]])
        XCTAssertEqual(userEntries[0]["name"] as? String, "user-own")
    }

    func testReinstallIsIdempotent() throws {
        let first = try DialHookInstaller.mergedSettings(
            existing: nil, target: .qoder, ctlPath: ctl
        )
        let second = try DialHookInstaller.mergedSettings(
            existing: first, target: .qoder, ctlPath: ctl
        )
        let root = try parse(second)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        for event in DialAgentTarget.claudeEvents {
            let groups = try XCTUnwrap(hooks[event] as? [[String: Any]])
            XCTAssertEqual(groups.count, 1, "duplicate group for \(event)")
        }
    }

    func testUninstallRemovesOnlyMarkerEntries() throws {
        let existing: [String: Any] = [
            "hooks": [
                "Stop": [
                    [
                        "matcher": "*",
                        "hooks": [
                            ["type": "command", "name": "user-own", "command": "/bin/true"],
                            ["type": "command", "name": "dialpilot", "command": "x"],
                        ],
                    ],
                ],
            ],
        ]
        let existingData = try JSONSerialization.data(withJSONObject: existing)
        let unmerged = try XCTUnwrap(
            DialHookInstaller.unmergedSettings(existing: existingData)
        )
        let root = try parse(unmerged)
        XCTAssertFalse(DialHookInstaller.containsMarker(in: root))
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let entries = try XCTUnwrap(groups[0]["hooks"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["name"] as? String, "user-own")
    }

    func testUninstallWithoutMarkerReturnsNil() throws {
        let existing = try JSONSerialization.data(withJSONObject: ["hooks": [String: Any]()])
        XCTAssertNil(try DialHookInstaller.unmergedSettings(existing: existing))
    }

    func testInvalidExistingJSONIsRejected() {
        let garbage = Data("{not json".utf8)
        XCTAssertThrowsError(
            try DialHookInstaller.mergedSettings(existing: garbage, target: .qoder, ctlPath: ctl)
        ) { error in
            XCTAssertEqual(error as? DialHookInstallerError, .invalidExistingJSON)
        }
    }

    func testQwenWorkAndDshRejectLocalMerge() {
        XCTAssertThrowsError(
            try DialHookInstaller.mergedSettings(existing: nil, target: .qwenwork, ctlPath: ctl)
        )
        XCTAssertThrowsError(
            try DialHookInstaller.mergedSettings(existing: nil, target: .dsh, ctlPath: ctl)
        )
    }

    func testDetectionWithTempHome() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("dialpilot-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent(".qoder"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }

        let qoder = DialHookInstaller.detect(target: .qoder, homeDirectory: home)
        XCTAssertTrue(qoder.detected)
        XCTAssertFalse(qoder.installed)

        let claude = DialHookInstaller.detect(target: .claudeCode, homeDirectory: home)
        XCTAssertFalse(claude.detected)

        // Installed flag flips after a merge is written.
        let settingsURL = home.appendingPathComponent(".qoder/settings.json")
        let merged = try DialHookInstaller.mergedSettings(existing: nil, target: .qoder, ctlPath: ctl)
        try merged.write(to: settingsURL)
        let after = DialHookInstaller.detect(target: .qoder, homeDirectory: home)
        XCTAssertTrue(after.installed)
    }

    // MARK: - Ctl protocol

    func testRequestRoundTrip() throws {
        let request = DialCtlProtocol.Request(
            command: "hook", agent: "qoder", session: "s1", event: "Stop", dialect: "claude"
        )
        let line = try DialCtlProtocol.encodeLine(request)
        XCTAssertEqual(line.last, 0x0A)
        let decoded = try XCTUnwrap(DialCtlProtocol.decodeRequest(line))
        XCTAssertEqual(decoded, request)
    }

    func testHookPayloadParsing() throws {
        let payload: [String: Any] = [
            "hook_event_name": "Notification",
            "session_id": "abc",
        ]
        let request = try XCTUnwrap(
            DialCtlProtocol.requestFromHookPayload(
                payload, agent: "claude-code", dialect: "claude", fallbackEvent: nil
            )
        )
        XCTAssertEqual(request.event, "Notification")
        XCTAssertEqual(request.session, "abc")
        XCTAssertEqual(request.command, "hook")
    }

    func testHookPayloadFallsBackToArgvEvent() {
        let request = DialCtlProtocol.requestFromHookPayload(
            [:], agent: "codex", dialect: "claude", fallbackEvent: "Stop"
        )
        XCTAssertEqual(request?.event, "Stop")
        XCTAssertEqual(request?.session, "default")
        XCTAssertNil(
            DialCtlProtocol.requestFromHookPayload(
                [:], agent: "codex", dialect: "claude", fallbackEvent: nil
            )
        )
    }
}