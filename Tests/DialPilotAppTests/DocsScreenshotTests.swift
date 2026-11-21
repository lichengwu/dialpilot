import XCTest
import AppKit
import DialPilotCore
@testable import DialPilotApp

/// Opt-in: `DIALPILOT_SNAPSHOT=1 swift test --filter DocsScreenshot`
///
/// Renders README screenshots at 2× with the real panel chrome (rounded card
/// + arrow) on a neutral backdrop. Kept out of normal runs so CI never
/// depends on /tmp artifacts or on font metrics of the host machine.
///
/// Output:
///   /tmp/dialpilot_docs_panel.png  — default state
///   /tmp/dialpilot_docs_hover.png  — chart hover on the third column
final class DocsScreenshotTests: XCTestCase {
    func testRenderDocsScreenshots() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DIALPILOT_SNAPSHOT"] != "1")

        var power = DialPowerSnapshot()
        power.battery = DialBatteryStatus(
            percent: 62, voltageMillivolts: 3900, isCharging: false,
            isFullyCharged: false, lowBatteryLevel: 0, isPoweredOff: false
        )
        let stats = Self.sampleUsage()

        let vc = SettingsViewController(configuration: .default)
        vc.update(
            configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, powerStatus: power, powerSaving: false,
            hardwareSyncInProgress: false, notice: nil, usageStats: stats
        )
        vc.currentLedState = .working
        _ = vc.view
        vc.view.layoutSubtreeIfNeeded()

        let content = vc.measuredContentSize()
        let panelSize = NSSize(
            width: DialPanelMetrics.width,
            height: content.height + DialPanelMetrics.arrowHeight
        )
        let container = PanelCanvas(frame: NSRect(origin: .zero, size: panelSize))
        container.appearance = NSAppearance(named: .darkAqua)

        let background = DialPanelBackgroundView(frame: container.bounds)
        background.arrowCenterX = panelSize.width / 2
        container.addSubview(background)

        vc.view.frame = NSRect(
            x: 0, y: 0, width: DialPanelMetrics.width, height: content.height
        )
        background.addSubview(vc.view)
        container.layoutSubtreeIfNeeded()

        try render(container, to: "/tmp/dialpilot_docs_panel.png")

        if let chart = container.firstDescendant(of: UsageBarChartView.self) {
            chart.hoveredIndex = 3
            chart.needsDisplay = true
            container.layoutSubtreeIfNeeded()
            try render(container, to: "/tmp/dialpilot_docs_hover.png")
        }
        print("docs screenshot size:", panelSize)
    }

    /// Mirrors the shape of real usage: a busy day, a quiet week behind it.
    private static func sampleUsage() -> DialUsageStats {
        var stats = DialUsageStats()
        let calendar = Calendar.current
        let today = Date()
        let plans: [(Int, Int)] = [(6, 45), (5, 38), (4, 31), (3, 24), (2, 17), (1, 10)]
        for (offset, count) in plans {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = DialUsageStats.dayKey(for: day)
            for i in 0..<count {
                stats.record(control: i % 5 == 0 ? .topButton : .knobRight, on: key)
            }
        }
        let todayKey = DialUsageStats.dayKey(for: today)
        for i in 0..<96 {
            let control: InputControl = i % 9 == 0 ? .knobPress : .knobRight
            stats.record(control: control, on: todayKey)
        }
        return stats
    }

    private func render(_ view: NSView, to path: String) throws {
        let scale: CGFloat = 2
        let width = Int((view.bounds.width * scale).rounded())
        let height = Int((view.bounds.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else {
            return XCTFail("could not allocate bitmap")
        }
        rep.size = view.bounds.size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return XCTFail("could not create graphics context")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Neutral backdrop: the card's hairline needs something to sit on,
        // and a desktop screenshot would leak whatever was open at the time.
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        view.bounds.fill()
        view.cacheDisplay(in: view.bounds, to: rep)
        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("could not encode png")
        }
        try png.write(to: URL(fileURLWithPath: path))
    }
}

/// Flat dark canvas with a very subtle vertical gradient, so the panel does
/// not float on a pure black rectangle in the README.
private final class PanelCanvas: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let gradient = NSGradient(
            starting: NSColor(calibratedWhite: 0.14, alpha: 1),
            ending: NSColor(calibratedWhite: 0.09, alpha: 1)
        )
        gradient?.draw(in: bounds, angle: -90)
    }
}

private extension NSView {
    func firstDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let nested = subview.firstDescendant(of: type) { return nested }
        }
        return nil
    }
}
