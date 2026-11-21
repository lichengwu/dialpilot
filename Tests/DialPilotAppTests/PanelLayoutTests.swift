import XCTest
import AppKit
import DialPilotCore
@testable import DialPilotApp

/// Panel layout regression: the guide is a separate window, so the panel
/// height never changes because of it. These tests pin the compact layout
/// and the "notice only on events" rule.
final class PanelLayoutTests: XCTestCase {
    private func makeVC() -> SettingsViewController {
        let vc = SettingsViewController(configuration: .default)
        vc.update(
            configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, powerStatus: DialPowerSnapshot(),
            powerSaving: false, hardwareSyncInProgress: false,
            notice: nil
        )
        _ = vc.view
        vc.view.layoutSubtreeIfNeeded()
        return vc
    }

    func testPanelHeightIsStableAcrossUpdates() {
        let vc = makeVC()
        let first = vc.preferredContentSize.height
        // A second update with identical state must not change the height
        // (no inline guide to expand/collapse anymore).
        vc.update(
            configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, powerStatus: DialPowerSnapshot(),
            powerSaving: false, hardwareSyncInProgress: false,
            notice: nil
        )
        vc.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(vc.preferredContentSize.height, first, accuracy: 1.0)
        XCTAssertLessThan(first, 480, "single-profile panel should be compact")
    }

    func testNoticeHiddenWhenIdle() {
        let vc = makeVC()
        let stack = vc.view.subviews.first as? NSStackView
        let noticeLabel = stack?.arrangedSubviews.compactMap { $0 as? NSTextField }
            .first { $0.maximumNumberOfLines == 2 }
        XCTAssertEqual(noticeLabel?.isHidden, true)
    }

    func testNoProfileSelectorOrMaintenanceButtons() {
        let vc = makeVC()
        // The single-profile design removed the profile selector, write-to-device, native/gesture
        // toggle, restart, and launch-at-login controls. The panel should
        // contain no segmented control for profiles and no such buttons.
        let segmented = vc.view.subviews.first.map { root in
            root.subviewsRecursive().compactMap { $0 as? NSSegmentedControl }
        } ?? []
        // Only the light-mode selector remains (3 segments: All On/Off/Smart).
        XCTAssertEqual(segmented.count, 1)
        XCTAssertEqual(segmented.first?.segmentCount, 3)
    }

    func testUsageCardHiddenUntilFirstEvent() {
        let vc = makeVC()
        let charts = vc.view.subviewsRecursive().compactMap { $0 as? UsageBarChartView }
        XCTAssertEqual(charts.count, 1)
        // Empty stats: the whole usage card (chart's superview) is hidden.
        XCTAssertEqual(charts.first?.superview?.isHidden, true)

        var stats = DialUsageStats()
        stats.record(control: .knobRight, on: DialUsageStats.dayKey(for: Date()))
        vc.update(
            configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, powerStatus: DialPowerSnapshot(),
            powerSaving: false, hardwareSyncInProgress: false,
            notice: nil, usageStats: stats
        )
        vc.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(charts.first?.superview?.isHidden, false)
        XCTAssertEqual(charts.first?.days.count, 7)
        XCTAssertEqual(charts.first?.days.last?.isToday, true)
    }

    func testBatteryRingShowsPercentAndNilState() {
        let vc = makeVC()
        let rings = vc.view.subviewsRecursive().compactMap { $0 as? BatteryRingView }
        XCTAssertEqual(rings.count, 1)
        XCTAssertNil(rings.first?.percent, "no reading must not fake a number")

        var power = DialPowerSnapshot()
        power.battery = DialBatteryStatus(
            percent: 62, voltageMillivolts: 3900,
            isCharging: false, isFullyCharged: false,
            lowBatteryLevel: 0, isPoweredOff: false
        )
        vc.update(
            configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, powerStatus: power,
            powerSaving: false, hardwareSyncInProgress: false,
            notice: nil
        )
        XCTAssertEqual(rings.first?.percent, 62)
    }
}

private extension NSView {
    func subviewsRecursive() -> [NSView] {
        subviews + subviews.flatMap { $0.subviewsRecursive() }
    }
}
/// Width regression (2026-11-21 user screenshot): dynamic labels must
/// truncate, never stretch the panel. Before the fix, active sessions
/// grew the panel to 522pt and it never shrank back — dead band on right.
final class PanelWidthTests: XCTestCase {
    func testWidthFixedAcrossDynamicContent() {
        for lang in [DialLanguage.english, .chinese] {
            L10n.language = lang
            let vc = SettingsViewController(configuration: .default)
            _ = vc.view
            vc.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(vc.preferredContentSize.width, 380, "base \(lang)")

            var agg = DialLedSessionAggregator()
            let now = Date().timeIntervalSince1970
            _ = agg.record(session: "s1", state: .working, now: now, agent: "codebuddy")
            _ = agg.record(session: "s2", state: .working, now: now, agent: "claude-code")
            _ = agg.record(session: "s3", state: .notification, now: now, agent: "qwenwork")
            var stats = DialUsageStats()
            for _ in 0..<50 { stats.record(control: .topButton, on: DialUsageStats.dayKey(for: Date())) }
            vc.update(
                configuration: .default, listenerActive: true,
                accessibilityGranted: true, inputMonitoringGranted: true,
                deviceConnected: true, powerStatus: DialPowerSnapshot(),
                powerSaving: false, hardwareSyncInProgress: false, notice: nil,
                usageStats: stats, activeSessions: agg.activeSessions(now: now)
            )
            vc.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(vc.preferredContentSize.width, 380, "sessions+stats \(lang)")

            vc.update(
                configuration: .default, listenerActive: true,
                accessibilityGranted: true, inputMonitoringGranted: true,
                deviceConnected: true, powerStatus: DialPowerSnapshot(),
                powerSaving: false, hardwareSyncInProgress: false,
                notice: "Wrote to device. Works after the app quits. App-only keys (voice / Fn double-tap) are empty offline and need the app.",
                usageStats: stats, activeSessions: agg.activeSessions(now: now)
            )
            vc.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(vc.preferredContentSize.width, 380, "long notice \(lang)")

            // No visible card may exceed the stack's right edge.
            if let stack = vc.view.subviews.first as? NSStackView {
                for (i, v) in stack.arrangedSubviews.enumerated() where !v.isHidden {
                    XCTAssertLessThanOrEqual(v.alignmentRect(forFrame: v.frame).maxX, stack.bounds.width + 0.5,
                                             "card \(i) overflows \(lang)")
                }
            }
        }
    }
}

/// Overflow regression: a card can be exactly 352pt wide while a *row inside
/// it* needs more, and AppKit then steals width from whichever control has
/// the lowest compression resistance. That is how the lights card rendered
/// "● Wo|" instead of "● Working" (2026-11-21). Nothing inside a stack may
/// stick out of it.
final class PanelOverflowTests: XCTestCase {
    func testNoSubtreeOverflowsItsStack() {
        for lang in [DialLanguage.english, .chinese] {
            L10n.language = lang
            let vc = SettingsViewController(configuration: .default)
            var stats = DialUsageStats()
            for _ in 0..<40 { stats.record(control: .knobRight, on: DialUsageStats.dayKey(for: Date())) }
            vc.update(
                configuration: .default, listenerActive: true,
                accessibilityGranted: true, inputMonitoringGranted: true,
                deviceConnected: true, powerStatus: DialPowerSnapshot(),
                powerSaving: false, hardwareSyncInProgress: false, notice: nil,
                usageStats: stats
            )
            vc.currentLedState = .working
            _ = vc.view
            vc.view.layoutSubtreeIfNeeded()

            var checked = 0
            for stack in vc.view.allStacks() where !stack.isHidden {
                for (index, child) in stack.arrangedSubviews.enumerated() where !child.isHidden {
                    checked += 1
                    XCTAssertLessThanOrEqual(
                        child.alignmentRect(forFrame: child.frame).maxX,
                        stack.bounds.width + 0.5,
                        "\(lang): \(type(of: stack))[\(index)] overflows by "
                            + "\(child.frame.maxX - stack.bounds.width)pt"
                    )
                }
            }
            XCTAssertGreaterThan(checked, 8, "walk must actually visit the rows")

            // The lights state token is the control that used to get squeezed
            // ("Wo…" instead of "Working") when the row was over-subscribed.
            let chip = vc.view.allDescendants()
                .compactMap { $0 as? NSTextField }
                .first { $0.identifier?.rawValue == "ledChip" }
            if let chip {
                XCTAssertGreaterThanOrEqual(
                    chip.frame.width + 0.5,
                    chip.intrinsicContentSize.width,
                    "\(lang): state chip is truncated"
                )
            } else {
                XCTFail("\(lang): state chip not found")
            }

            // Buttons must keep their intrinsic width too — a squeezed
            // button renders as a clipped label, which is how the Connect
            // button lost its tail before the lights card got three rows.
            // Popups size themselves to a fixed width on purpose; only plain
            // push buttons must keep their intrinsic width.
            let pushButtons = vc.view.allDescendants()
                .compactMap { $0 as? NSButton }
                .filter { !$0.isHidden && !($0 is NSPopUpButton) }
            for button in pushButtons {
                XCTAssertGreaterThanOrEqual(
                    button.frame.width + 0.5,
                    button.intrinsicContentSize.width,
                    "\(lang): button '\(button.title)' is squeezed"
                )
            }
        }
    }
}

private extension NSView {
    func allDescendants() -> [NSView] {
        subviews + subviews.flatMap { $0.allDescendants() }
    }
}

private extension NSView {
    func allStacks() -> [NSStackView] {
        let selfMatch = (self as? NSStackView).map { [$0] } ?? []
        return selfMatch + subviews.flatMap { $0.allStacks() }
    }
}
