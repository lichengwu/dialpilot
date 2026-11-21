import XCTest
import AppKit
@testable import DialPilotApp

/// Panel placement regression for the menu-bar-manager case: the window
/// must stay exactly content-sized and glued to the item.
///
/// The old NSPopover decided its own size and position, and once a menu-bar
/// manager moved the status item it came back as a ~1900×580 grey field with
/// the 380pt card stuck in the corner. These tests pin the invariants that
/// make that impossible: the window is exactly content + arrow, it sits
/// under the anchor, it stays on screen, and the arrow always points at the
/// icon while staying on the rounded body.
final class DialPanelGeometryTests: XCTestCase {
    /// 1920×1080 display with a 25pt menu bar: what AppKit hands us as
    /// `visibleFrame` for a screen whose menu bar is at the top.
    private let screen = NSRect(x: 0, y: 0, width: 1920, height: 1055)

    /// Status item icon: 22×22, sitting in the menu bar.
    private func anchor(midX: CGFloat) -> NSRect {
        NSRect(x: midX - 11, y: 1057, width: 22, height: 22)
    }

    private var arrowLowest: CGFloat {
        DialPanelMetrics.cornerRadius + DialPanelMetrics.arrowWidth / 2
    }
    private var arrowHighest: CGFloat {
        DialPanelMetrics.width - DialPanelMetrics.cornerRadius - DialPanelMetrics.arrowWidth / 2
    }

    func testWindowIsExactlyContentPlusArrow() {
        let placed = DialPanelGeometry.placement(
            anchor: anchor(midX: 960), contentHeight: 600, screen: screen
        )
        XCTAssertEqual(placed.frame.width, DialPanelMetrics.width, accuracy: 0.5)
        XCTAssertEqual(
            placed.frame.height, 600 + DialPanelMetrics.arrowHeight, accuracy: 0.5,
            "the window must be exactly the content plus the arrow — no slack"
        )
        XCTAssertEqual(
            placed.frame.maxY, 1057 + DialPanelMetrics.topGap, accuracy: 0.5,
            "the panel hangs from the menu bar"
        )
        XCTAssertEqual(placed.frame.midX, 960, accuracy: 0.5, "centred under the icon")
        XCTAssertEqual(placed.arrowCenterX, placed.frame.width / 2, accuracy: 0.5)
    }

    func testShorterContentShrinksTheWindowAndKeepsTheTopEdge() {
        let tall = DialPanelGeometry.placement(
            anchor: anchor(midX: 960), contentHeight: 600, screen: screen
        )
        let short = DialPanelGeometry.placement(
            anchor: anchor(midX: 960), contentHeight: 320, screen: screen
        )
        XCTAssertEqual(tall.frame.maxY, short.frame.maxY, accuracy: 0.5)
        XCTAssertEqual(tall.frame.height - short.frame.height, 280, accuracy: 0.5)
    }

    func testIconAtRightEdgeKeepsPanelOnScreen() {
        let placed = DialPanelGeometry.placement(
            anchor: anchor(midX: 1912), contentHeight: 500, screen: screen
        )
        XCTAssertEqual(
            placed.frame.maxX, 1920 - DialPanelMetrics.screenMargin, accuracy: 0.5,
            "must not hang off the right edge"
        )
        XCTAssertLessThanOrEqual(placed.arrowCenterX, arrowHighest + 0.5)
        XCTAssertGreaterThanOrEqual(placed.arrowCenterX, arrowLowest - 0.5)
    }

    func testIconAtLeftEdgeKeepsPanelOnScreen() {
        let placed = DialPanelGeometry.placement(
            anchor: anchor(midX: 8), contentHeight: 500, screen: screen
        )
        XCTAssertEqual(placed.frame.minX, DialPanelMetrics.screenMargin, accuracy: 0.5)
        XCTAssertEqual(placed.arrowCenterX, arrowLowest, accuracy: 0.5)
    }

    func testArrowStaysOnTheRoundedBodyAcrossTheWholeMenuBar() {
        for midX in stride(from: CGFloat(0), through: 1920, by: 7) {
            let placed = DialPanelGeometry.placement(
                anchor: anchor(midX: midX), contentHeight: 420, screen: screen
            )
            XCTAssertGreaterThanOrEqual(placed.arrowCenterX, arrowLowest - 0.5, "midX \(midX)")
            XCTAssertLessThanOrEqual(placed.arrowCenterX, arrowHighest + 0.5, "midX \(midX)")
        }
    }

    func testArrowTracksTheIconWhenItFits() {
        for midX in stride(from: CGFloat(300), through: 1600, by: 100) {
            let placed = DialPanelGeometry.placement(
                anchor: anchor(midX: midX), contentHeight: 420, screen: screen
            )
            let absoluteArrow = placed.frame.minX + placed.arrowCenterX
            XCTAssertEqual(absoluteArrow, midX, accuracy: 0.5, "midX \(midX)")
        }
    }

    func testTallContentNeverCoversTheMenuBar() {
        let placed = DialPanelGeometry.placement(
            anchor: anchor(midX: 960), contentHeight: 4000, screen: screen
        )
        XCTAssertEqual(placed.frame.maxY, 1057 + DialPanelMetrics.topGap, accuracy: 0.5)
        XCTAssertEqual(
            placed.frame.minY, DialPanelMetrics.screenMargin, accuracy: 0.5,
            "clipped at the screen bottom instead of growing over the menu bar"
        )
    }

    func testMinimumHeightFloor() {
        let placed = DialPanelGeometry.placement(
            anchor: anchor(midX: 960), contentHeight: 10, screen: screen
        )
        XCTAssertEqual(
            placed.frame.height,
            DialPanelMetrics.minContentHeight + DialPanelMetrics.arrowHeight,
            accuracy: 0.5
        )
    }
}
