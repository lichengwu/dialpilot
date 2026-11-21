import XCTest
import AppKit
import DialPilotCore
@testable import DialPilotApp

/// Opt-in visual snapshot: DIALPILOT_SNAPSHOT=1 swift test --filter PanelSnapshot
/// Renders the real panel offscreen to /tmp/dialpilot_panel_v6.png.
/// Skipped in normal runs — CI must not depend on /tmp artifacts.
final class PanelSnapshotTests: XCTestCase {
    func testRenderPanelSnapshot() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DIALPILOT_SNAPSHOT"] != "1")
        var power = DialPowerSnapshot()
        power.battery = DialBatteryStatus(percent: 62, voltageMillivolts: 3900,
            isCharging: false, isFullyCharged: false, lowBatteryLevel: 0, isPoweredOff: false)
        var stats = DialUsageStats()
        let today = DialUsageStats.dayKey(for: Date())
        for (control, n) in [(InputControl.knobRight, 34), (.knobLeft, 21), (.knobPress, 12), (.topButton, 8), (.middleButton, 15), (.bottomButton, 6)] {
            for _ in 0..<n { stats.record(control: control, on: today) }
        }
        for offset in 1...6 {
            let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
            let key = DialUsageStats.dayKey(for: d)
            for _ in 0..<(offset * 7 + 3) { stats.record(control: .knobRight, on: key) }
        }
        let vc = SettingsViewController(configuration: .default)
        vc.update(configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, powerStatus: power, powerSaving: false,
            hardwareSyncInProgress: false, notice: nil, usageStats: stats)
        vc.currentLedState = .working
        _ = vc.view
        vc.view.layoutSubtreeIfNeeded()
        let size = vc.preferredContentSize
        vc.view.frame = NSRect(origin: .zero, size: size)
        vc.view.appearance = NSAppearance(named: .aqua)
        vc.view.layoutSubtreeIfNeeded()
        let scale: CGFloat = 1
        let img = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale))
        img.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale).fill()
        NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
        vc.view.displayIgnoringOpacity(vc.view.bounds, in: NSGraphicsContext.current!)
        img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: "/tmp/dialpilot_panel_v6.png"))

        // Hover variant: simulate the cursor on the 3rd column and render
        // the detail-row state to a second file.
        let charts = vc.view.subviewsRecursive().compactMap { $0 as? UsageBarChartView }
        if let chart = charts.first {
            chart.hoveredIndex = 2
            chart.needsDisplay = true
            let img2 = NSImage(size: NSSize(width: size.width * scale, height: size.height * scale))
            img2.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale).fill()
            NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
            vc.view.displayIgnoringOpacity(vc.view.bounds, in: NSGraphicsContext.current!)
            img2.unlockFocus()
            let png2 = NSBitmapImageRep(data: img2.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try png2.write(to: URL(fileURLWithPath: "/tmp/dialpilot_panel_v6_hover.png"))
        }
        print("SNAPSHOT panel size:", size)
        print("view frame:", vc.view.frame)
        if let stack = vc.view.subviews.first as? NSStackView {
            print("stack frame:", stack.frame)
            for (i, v) in stack.arrangedSubviews.enumerated() {
                print("card \(i):", v.frame, "hidden:", v.isHidden)
                if let inner = v as? NSStackView {
                    for (j, iv) in inner.arrangedSubviews.enumerated() {
                        print("  inner \(i).\(j):", type(of: iv), iv.frame, "fitting:", iv.fittingSize)
                        if let g = iv as? NSGridView {
                            print("    col0:", g.column(at: 0).width, "col1:", g.column(at: 1).width)
                            if let cell = g.cell(atColumnIndex: 1, rowIndex: 0).contentView as? NSPopUpButton {
                                print("    popup fitting:", cell.fittingSize, "intrinsic:", cell.intrinsicContentSize)
                                for item in cell.itemArray.prefix(30) { print("    item:", item.title) }
                            }
                        }
                    }
                }
            }
        }
    }
}

private extension NSView {
    func subviewsRecursive() -> [NSView] {
        subviews + subviews.flatMap { $0.subviewsRecursive() }
    }
}

/// Opt-in hooks-window snapshot (same env gate as the panel snapshot).
final class HooksWindowSnapshotTests: XCTestCase {
    func testRenderHooksWindowSnapshot() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DIALPILOT_SNAPSHOT"] != "1")
        let controller = AgentHooksWindowController()
        guard let window = controller.window, let content = window.contentView else {
            return XCTFail("no window")
        }
        window.appearance = NSAppearance(named: .darkAqua)
        content.layoutSubtreeIfNeeded()
        let size = content.frame.size
        // 2× like the other README shots, so the docs do not mix pixel
        // densities and font weights.
        let scale: CGFloat = 2
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        content.cacheDisplay(in: content.bounds, to: rep)
        NSGraphicsContext.restoreGraphicsState()
        let png = rep.representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: "/tmp/dialpilot_hooks_window.png"))
        print("HOOKS SNAPSHOT size:", size)
    }
}

/// Opt-in: DIALPILOT_SNAPSHOT=1 swift test --filter PanelSnapshot
/// Renders the "USB enumerated, knob switched off" panel to
/// /tmp/dialpilot_panel_offline.png so the copy can be reviewed without a
/// physical device in that state.
final class PanelOfflineSnapshotTests: XCTestCase {
    func testRenderPoweredOffPanelSnapshot() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["DIALPILOT_SNAPSHOT"] != "1")
        let vc = SettingsViewController(configuration: .default)
        vc.update(
            configuration: .default, listenerActive: true,
            accessibilityGranted: true, inputMonitoringGranted: true,
            deviceConnected: true, deviceResponsive: false,
            powerStatus: DialPowerSnapshot(), powerSaving: false,
            hardwareSyncInProgress: false, notice: nil
        )
        _ = vc.view
        vc.view.layoutSubtreeIfNeeded()
        let size = vc.preferredContentSize
        vc.view.frame = NSRect(origin: .zero, size: size)
        vc.view.appearance = NSAppearance(named: .darkAqua)
        vc.view.layoutSubtreeIfNeeded()
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        vc.view.displayIgnoringOpacity(vc.view.bounds, in: NSGraphicsContext.current!)
        img.unlockFocus()
        let png = NSBitmapImageRep(data: img.tiffRepresentation!)!
            .representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: "/tmp/dialpilot_panel_offline.png"))
    }
}
