import XCTest
@testable import DialPilotCore

/// Usage statistics: pure counters, day keys, retention, recent-window
/// queries, and JSON round-trip. No HID, no timers.
final class DialUsageStatsTests: XCTestCase {
    func testRecordIncrementsTotalsAndDaily() {
        var stats = DialUsageStats()
        stats.record(control: .knobRight, on: "2026-11-21")
        stats.record(control: .knobRight, on: "2026-11-21")
        stats.record(control: .topButton, on: "2026-11-21")
        XCTAssertEqual(stats.count(for: .knobRight), 2)
        XCTAssertEqual(stats.count(for: .topButton), 1)
        XCTAssertEqual(stats.count(onDay: "2026-11-21"), 3)
        XCTAssertEqual(stats.lifetimeTotal, 3)
    }

    func testTopControlAndEmptyState() {
        var stats = DialUsageStats()
        XCTAssertNil(stats.topControl)
        XCTAssertEqual(stats.lifetimeTotal, 0)
        stats.record(control: .middleButton, on: "2026-11-21")
        stats.record(control: .middleButton, on: "2026-11-21")
        stats.record(control: .knobLeft, on: "2026-11-21")
        XCTAssertEqual(stats.topControl, .middleButton)
    }

    func testRecentDaysFillsMissingWithZeroOldestFirst() {
        var stats = DialUsageStats()
        stats.record(control: .knobPress, on: "2026-11-19")
        stats.record(control: .knobPress, on: "2026-11-21")
        stats.record(control: .knobPress, on: "2026-11-21")
        let window = stats.recentDays(3, today: "2026-11-21")
        XCTAssertEqual(window.map(\.day), ["2026-11-19", "2026-11-20", "2026-11-21"])
        XCTAssertEqual(window.map(\.count), [1, 0, 2])
    }

    func testRetentionPrunesOldDaysButKeepsTotals() {
        var stats = DialUsageStats()
        let day = makeDay(2026, 11, 21)
        // 100 consecutive days ending at the anchor: 90 survive.
        for offset in (0..<100).reversed() {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: day)!
            stats.record(control: .bottomButton, on: DialUsageStats.dayKey(for: date))
        }
        XCTAssertEqual(stats.daily.count, DialUsageStats.retentionDays)
        XCTAssertEqual(stats.count(for: .bottomButton), 100, "lifetime totals never pruned")
    }

    /// Retention is a calendar window, not "keep the newest N keys": a sparse
    /// user must still lose months-old days, otherwise the window silently
    /// stretches as far back as the file goes.
    func testRetentionDropsStaleDaysEvenWhenFewDaysExist() {
        var stats = DialUsageStats()
        stats.record(control: .knobPress, on: "2026-01-05")
        stats.record(control: .knobPress, on: "2026-11-20")
        XCTAssertEqual(stats.count(onDay: "2026-01-05"), 0)
        XCTAssertEqual(stats.count(onDay: "2026-11-20"), 1)
        XCTAssertEqual(stats.count(for: .knobPress), 2, "totals are lifetime")
    }

    /// A hand-edited or clock-skewed day key must not disable pruning
    /// entirely; the fallback caps the file at `retentionDays` entries.
    func testUnparsableDayKeysFallBackToCountBasedPruning() {
        var stats = DialUsageStats()
        for i in 1...95 {
            stats.record(control: .topButton, on: "bogus-\(i)")
        }
        XCTAssertLessThanOrEqual(stats.daily.count, DialUsageStats.retentionDays)
    }

    func testDayKeyUsesLocalCalendar() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 21
        components.hour = 23; components.minute = 59
        let date = calendar.date(from: components)!
        XCTAssertEqual(DialUsageStats.dayKey(for: date, calendar: calendar), "2026-11-21")
    }

    func testJSONRoundTrip() throws {
        var stats = DialUsageStats()
        stats.record(control: .knobLeft, on: "2026-11-21")
        stats.record(control: .topButton, on: "2026-11-20")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try stats.save(to: url)
        XCTAssertEqual(DialUsageStats.load(from: url), stats)
    }

    func testCorruptOrMissingFileYieldsEmptyStats() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-missing-\(UUID().uuidString).json")
        XCTAssertEqual(DialUsageStats.load(from: missing), DialUsageStats())
        let corrupt = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-corrupt-\(UUID().uuidString).json")
        try? Data("not json".utf8).write(to: corrupt)
        defer { try? FileManager.default.removeItem(at: corrupt) }
        XCTAssertEqual(DialUsageStats.load(from: corrupt), DialUsageStats())
    }
}
/// Per-day per-control breakdown: powers chart hover tooltips.
final class DialUsageStatsDailyControlsTests: XCTestCase {
    func testTopControlPerDay() {
        var stats = DialUsageStats()
        stats.record(control: .knobRight, on: "2026-11-20")
        stats.record(control: .knobRight, on: "2026-11-20")
        stats.record(control: .topButton, on: "2026-11-20")
        stats.record(control: .bottomButton, on: "2026-11-21")
        XCTAssertEqual(stats.topControl(onDay: "2026-11-20"), .knobRight)
        XCTAssertEqual(stats.topControl(onDay: "2026-11-21"), .bottomButton)
        XCTAssertNil(stats.topControl(onDay: "2026-11-19"))
    }

    func testLegacyFileWithoutDailyControlsDecodes() throws {
        let json = """
        {"totals":{"knobRight":3},"daily":{"2026-11-21":3}}
        """
        let stats = try JSONDecoder().decode(DialUsageStats.self, from: Data(json.utf8))
        XCTAssertEqual(stats.lifetimeTotal, 3)
        XCTAssertTrue(stats.dailyControls.isEmpty)
        XCTAssertNil(stats.topControl(onDay: "2026-11-21"))
    }

    func testPruneDropsDailyControlsToo() {
        var stats = DialUsageStats()
        let day = makeDay(2026, 11, 21)
        for offset in (0..<100).reversed() {
            let date = Calendar.current.date(byAdding: .day, value: -offset, to: day)!
            stats.record(control: .knobLeft, on: DialUsageStats.dayKey(for: date))
        }
        XCTAssertEqual(stats.dailyControls.count, stats.daily.count)
        XCTAssertEqual(stats.dailyControls.count, DialUsageStats.retentionDays)
    }

    func testRoundTripIncludesDailyControls() throws {
        var stats = DialUsageStats()
        stats.record(control: .middleButton, on: "2026-11-21")
        let data = try JSONEncoder().encode(stats)
        let back = try JSONDecoder().decode(DialUsageStats.self, from: data)
        XCTAssertEqual(back, stats)
        XCTAssertEqual(back.topControl(onDay: "2026-11-21"), .middleButton)
    }

}

/// Noon on a given local day — keeps day-key tests out of DST edges.
private func makeDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    return Calendar.current.date(from: components)!
}
