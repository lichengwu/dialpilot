import AppKit
import DialPilotCore

/// Battery ring gauge — the iStat-style "big number inside a ring".
/// Percent in the middle (large), state caption under it (small),
/// arc colored by the same green/yellow/red rule as the old dot.
final class BatteryRingView: NSView {
    var percent: Int? {
        didSet {
            needsDisplay = true
            updateAccessibilityLabel()
        }
    }
    var caption: String = "" {
        didSet {
            needsDisplay = true
            updateAccessibilityLabel()
        }
    }
    var ringColor: NSColor = .secondaryLabelColor {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 76),
            heightAnchor.constraint(equalToConstant: 76),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        updateAccessibilityLabel()
    }

    /// The gauge is drawn, so VoiceOver has nothing to read without this.
    private func updateAccessibilityLabel() {
        let value = percent.map { "\($0)%" } ?? "—"
        let suffix = caption.isEmpty ? "" : ", \(caption)"
        setAccessibilityLabel("\(L10n.text(.battery)): \(value)\(suffix)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2 - 3

        // Track.
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 5
        NSColor.quaternaryLabelColor.withAlphaComponent(0.25).setStroke()
        track.stroke()

        // Value arc: clockwise from 12 o'clock.
        if let percent, percent > 0 {
            let arc = NSBezierPath()
            let end = 90 - 360 * CGFloat(min(percent, 100)) / 100
            arc.appendArc(
                withCenter: center, radius: radius,
                startAngle: 90, endAngle: end, clockwise: true
            )
            arc.lineWidth = 5
            arc.lineCapStyle = .round
            ringColor.setStroke()
            arc.stroke()
        }

        // Big number.
        let valueText = percent.map { "\($0)" } ?? "–"
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        drawCentered(valueText, font: valueFont, color: .labelColor,
                     center: center, dy: percent == nil ? 0 : 6)

        // Small unit + caption.
        if percent != nil {
            drawCentered("%", font: .systemFont(ofSize: 10, weight: .medium),
                         color: .secondaryLabelColor,
                         center: NSPoint(x: center.x + percentWidth(valueText, font: valueFont) / 2 + 6, y: center.y),
                         dy: 10)
        }
        drawCentered(caption, font: .systemFont(ofSize: 10),
                     color: .secondaryLabelColor, center: center, dy: -14)
    }

    private func percentWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, center: NSPoint, dy: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(
            at: NSPoint(x: center.x - size.width / 2, y: center.y + dy - size.height / 2),
            withAttributes: attrs
        )
    }
}

/// Seven-day usage bar chart with an iStat-style hover detail row.
/// Bars scale to the window max; today is accent-colored, older days
/// muted. Every non-zero bar carries its count on top. Hovering a column
/// highlights it and swaps the reserved top row from the window summary
/// to that day's detail (full date · count · top control) — the detail
/// lives inside the card, not in a delayed system tooltip.
final class UsageBarChartView: NSView {
    struct Day {
        let label: String
        let count: Int
        let isToday: Bool
        /// Full `yyyy-MM-dd` key, for the hover detail row.
        var fullDate: String = ""
        /// Most-used control that day (nil when the day is empty).
        var topControlName: String?
    }

    var days: [Day] = [] {
        didSet {
            hoveredIndex = nil
            needsDisplay = true
            rebuildTrackingAreas()
            updateAccessibilityLabel()
        }
    }

    var hoveredIndex: Int?
    private var barTrackingAreas: [NSTrackingArea] = []
    private static let detailRowHeight: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 92).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    /// One readable summary for the whole chart: the bars are painted, and a
    /// hover-only detail row is invisible to assistive technology.
    private func updateAccessibilityLabel() {
        guard !days.isEmpty else {
            setAccessibilityLabel("")
            return
        }
        let total = days.reduce(0) { $0 + $1.count }
        let perDay = days.map { "\($0.label) \($0.count)" }.joined(separator: ", ")
        setAccessibilityLabel("\(L10n.text(.usageLast7Days)): \(total) — \(perDay)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingAreas()
    }

    private func rebuildTrackingAreas() {
        barTrackingAreas.forEach(removeTrackingArea)
        barTrackingAreas.removeAll()
        guard !days.isEmpty, bounds.width > 0 else { return }
        let slot = bounds.width / CGFloat(days.count)
        for (i, _) in days.enumerated() {
            // Whole column is the hover target, not just the bar pixels —
            // a 2pt zero-day bar is impossible to hit with a cursor.
            //
            // Deliberately no `.inVisibleRect`: that option makes AppKit
            // ignore `rect` and use the whole view, so every column would
            // report the same index and hover would always name the last day.
            let rect = NSRect(x: CGFloat(i) * slot, y: 0, width: slot, height: bounds.height)
            let area = NSTrackingArea(
                rect: rect,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: ["dayIndex": i]
            )
            addTrackingArea(area)
            barTrackingAreas.append(area)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard let index = event.trackingArea?.userInfo?["dayIndex"] as? Int,
              index < days.count else { return }
        hoveredIndex = index
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !days.isEmpty else { return }
        drawDetailRow()

        let maxCount = max(days.map(\.count).max() ?? 0, 1)
        let labelHeight: CGFloat = 14
        let countHeight: CGFloat = 13
        let chartBottom = labelHeight + 2
        let chartHeight = bounds.height - Self.detailRowHeight - labelHeight - countHeight - 6
        let slot = bounds.width / CGFloat(days.count)
        let barWidth = min(slot * 0.55, 18)

        for (i, day) in days.enumerated() {
            // Hover highlight: a subtle full-column wash behind the bar.
            if hoveredIndex == i {
                let wash = NSBezierPath(
                    roundedRect: NSRect(x: CGFloat(i) * slot + 1, y: 0,
                                        width: slot - 2, height: bounds.height - Self.detailRowHeight),
                    xRadius: 5, yRadius: 5
                )
                NSColor.quaternaryLabelColor.withAlphaComponent(0.12).setFill()
                wash.fill()
            }

            let x = CGFloat(i) * slot + (slot - barWidth) / 2
            let height = day.count == 0 ? 2 : max(3, chartHeight * CGFloat(day.count) / CGFloat(maxCount))
            let rect = NSRect(x: x, y: chartBottom, width: barWidth, height: height)
            let bar = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
            let isHovered = hoveredIndex == i
            (day.isToday || isHovered
                ? NSColor.controlAccentColor
                : NSColor.secondaryLabelColor.withAlphaComponent(day.count == 0 ? 0.18 : 0.35)).setFill()
            bar.fill()

            // Count above every non-zero bar. Zero days stay silent —
            // a row of "0"s would be noise, the flat stub already says it.
            if day.count > 0 {
                let countText = "\(day.count)" as NSString
                let countFont = NSFont.monospacedDigitSystemFont(
                    ofSize: 10, weight: isHovered || day.isToday ? .semibold : .medium
                )
                let countColor: NSColor = day.isToday || isHovered ? .labelColor : .secondaryLabelColor
                let countAttrs: [NSAttributedString.Key: Any] = [.font: countFont, .foregroundColor: countColor]
                let countSize = countText.size(withAttributes: countAttrs)
                countText.draw(
                    at: NSPoint(
                        x: CGFloat(i) * slot + (slot - countSize.width) / 2,
                        y: rect.maxY + 2
                    ),
                    withAttributes: countAttrs
                )
            }

            // Day-of-month label.
            let label = day.label
            let font = NSFont.systemFont(ofSize: 9, weight: isHovered ? .semibold : .regular)
            let color: NSColor = day.isToday || isHovered ? .labelColor : .secondaryLabelColor
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (label as NSString).size(withAttributes: attrs)
            (label as NSString).draw(
                at: NSPoint(x: CGFloat(i) * slot + (slot - size.width) / 2, y: 0),
                withAttributes: attrs
            )
        }
    }

    /// Top row: hovered day's detail, or the window summary when idle.
    /// Always occupies the same height so the chart never jumps on hover.
    private func drawDetailRow() {
        let text: String
        let color: NSColor
        if let index = hoveredIndex, index < days.count {
            let day = days[index]
            var detail = day.fullDate.isEmpty ? day.label : day.fullDate
            detail += " · \(day.count)" + L10n.text(.usageTimesSuffix)
            if let top = day.topControlName {
                detail += " · " + top
            }
            text = detail
            color = .labelColor
        } else {
            let total = days.reduce(0) { $0 + $1.count }
            text = L10n.text(.usageLast7Days) + " · \(total)" + L10n.text(.usageTimesSuffix)
            color = .secondaryLabelColor
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: hoveredIndex == nil ? .regular : .medium),
            .foregroundColor: color,
        ]
        (text as NSString).draw(
            at: NSPoint(x: 2, y: bounds.height - Self.detailRowHeight + 2),
            withAttributes: attrs
        )
    }
}