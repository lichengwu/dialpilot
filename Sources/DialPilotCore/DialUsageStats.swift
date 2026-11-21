import Foundation

/// Local usage statistics for the dial. Pure counters + JSON persistence;
/// no network, no identifiers beyond control names and calendar days.
///
/// What is counted: one increment per *performed* control event — a knob
/// detent (left/right), a resolved single/double press, a button tap or
/// hold-start. Events that fire no action (binding = none) are still
/// device usage and are counted; failed action delivery is not.
///
/// Storage: `usage.json` next to config.json in Application Support.
/// Days are local-calendar `yyyy-MM-dd` strings; only the most recent
/// `retentionDays` are kept so the file cannot grow without bound.
public struct DialUsageStats: Codable, Equatable, Sendable {
    /// Per-control lifetime counts. Keys are InputControl raw values.
    public var totals: [String: Int]
    /// Per-day total event counts. Keys are `yyyy-MM-dd` (local calendar).
    public var daily: [String: Int]
    /// Per-day per-control counts: day → control raw value → count.
    /// Powers the chart hover ("that day's most-used control"). Optional
    /// in the JSON so files written by earlier builds decode unchanged.
    public var dailyControls: [String: [String: Int]]

    public static let retentionDays = 90

    public init(
        totals: [String: Int] = [:],
        daily: [String: Int] = [:],
        dailyControls: [String: [String: Int]] = [:]
    ) {
        self.totals = totals
        self.daily = daily
        self.dailyControls = dailyControls
    }

    private enum CodingKeys: String, CodingKey {
        case totals, daily, dailyControls
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totals = try container.decodeIfPresent([String: Int].self, forKey: .totals) ?? [:]
        daily = try container.decodeIfPresent([String: Int].self, forKey: .daily) ?? [:]
        dailyControls = try container.decodeIfPresent([String: [String: Int]].self, forKey: .dailyControls) ?? [:]
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Records one performed event. `day` is injectable for tests.
    public mutating func record(control: InputControl, on day: String) {
        totals[control.rawValue, default: 0] += 1
        daily[day, default: 0] += 1
        dailyControls[day, default: [:]][control.rawValue, default: 0] += 1
        prune(keepingDays: Self.retentionDays, today: day)
    }

    /// The control with the highest count on a given day; nil when empty.
    public func topControl(onDay day: String) -> InputControl? {
        dailyControls[day]?.max { a, b in
            a.value == b.value ? a.key > b.key : a.value < b.value
        }.flatMap { InputControl(rawValue: $0.key) }
    }

    public var lifetimeTotal: Int { totals.values.reduce(0, +) }

    public func count(for control: InputControl) -> Int {
        totals[control.rawValue] ?? 0
    }

    public func count(onDay day: String) -> Int { daily[day] ?? 0 }

    /// The control with the highest lifetime count; nil when nothing used.
    public var topControl: InputControl? {
        totals.max { a, b in
            a.value == b.value ? a.key > b.key : a.value < b.value
        }.flatMap { InputControl(rawValue: $0.key) }
    }

    /// Counts for the last `days` days ending at `today` (inclusive),
    /// oldest first. Missing days read as 0.
    public func recentDays(_ days: Int, today: String, calendar: Calendar = .current) -> [(day: String, count: Int)] {
        guard days > 0, let end = Self.date(from: today, calendar: calendar) else { return [] }
        return (0..<days).reversed().compactMap { offset in
            guard let d = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = Self.dayKey(for: d, calendar: calendar)
            return (key, daily[key] ?? 0)
        }
    }

    /// Drops day entries that fall outside the retention window ending at
    /// `today`. Totals are lifetime and never pruned.
    ///
    /// Pruning is calendar-based, not count-based: someone who uses the dial
    /// twice a month should still lose history older than the window, and an
    /// unusual burst of days must not evict recent entries. `today` is the
    /// just-recorded event's day, so the window always moves forward with
    /// real usage. If it cannot be parsed (hand-edited file), fall back to
    /// keeping the newest `keepingDays` keys — never grow unbounded.
    public mutating func prune(keepingDays: Int, today: String) {
        guard keepingDays > 0 else { return }
        let cutoff: String
        if let end = Self.date(from: today, calendar: .current),
           let start = Calendar.current.date(byAdding: .day, value: -(keepingDays - 1), to: end) {
            cutoff = Self.dayKey(for: start)
        } else {
            let keys = daily.keys.sorted()
            guard keys.count > keepingDays else { return }
            for key in keys.prefix(keys.count - keepingDays) {
                daily.removeValue(forKey: key)
                dailyControls.removeValue(forKey: key)
            }
            return
        }
        // `yyyy-MM-dd` sorts lexicographically in chronological order.
        for key in Set(daily.keys).union(dailyControls.keys) where key < cutoff {
            daily.removeValue(forKey: key)
            dailyControls.removeValue(forKey: key)
        }
    }

    private static func date(from dayKey: String, calendar: Calendar) -> Date? {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        c.hour = 12
        return calendar.date(from: c)
    }

    // MARK: - Persistence

    public static func defaultURL(fileManager: FileManager = .default) throws -> URL {
        try ConfigStore.defaultConfigURL(fileManager: fileManager)
            .deletingLastPathComponent()
            .appendingPathComponent("usage.json", isDirectory: false)
    }

    /// Loads stats; a missing or corrupt file yields empty stats — usage
    /// history is nice-to-have and must never block the app.
    public static func load(from url: URL, fileManager: FileManager = .default) -> DialUsageStats {
        guard let data = try? Data(contentsOf: url),
              let stats = try? JSONDecoder().decode(DialUsageStats.self, from: data)
        else { return DialUsageStats() }
        return stats
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}