import AppKit
import DialPilotCore

/// Menu-bar status icon: AU05 dial silhouette + one exception badge.
///
/// Design (approved 2026-11-21): the menu bar only reports exceptions.
/// Normal = bare glyph (template image, macOS tints it). Exceptions get
/// a colored dot at the bottom-right, or a faded dashed body when the
/// device is gone. Colored badges cannot live in a template image
/// (macOS would tint them monochrome), so badge variants are drawn
/// non-template with an explicit light/dark body color.
enum DialStatusIcon {
    static func image(for state: DialStatusBarState, darkMenuBar: Bool) -> NSImage? {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            draw(state: state, darkMenuBar: darkMenuBar)
            return true
        }
        // Only the badge-free normal glyph can be a template image.
        image.isTemplate = state == .normal
        image.accessibilityDescription = "DialPilot"
        return image
    }

    private static func draw(state: DialStatusBarState, darkMenuBar: Bool) {
        let bodyColor: NSColor = state == .normal
            ? .black  // template: tinted by macOS
            : (darkMenuBar ? .white : NSColor(white: 0.13, alpha: 1))

        if state == .disconnected {
            NSGraphicsContext.current?.cgContext.setAlpha(0.45)
        }
        bodyColor.setStroke()
        bodyColor.setFill()

        // Body: tall rounded rectangle, centered (single profile, no badge
        // on the top-right anymore — the status dot owns bottom-right).
        let body = NSBezierPath(
            roundedRect: NSRect(x: 4.5, y: 1.5, width: 9.0, height: 15.0),
            xRadius: 2.6,
            yRadius: 2.6
        )
        body.lineWidth = 1.3
        if state == .disconnected {
            body.setLineDash([2.2, 1.6], count: 2, phase: 0)
        }
        body.stroke()

        // Rotary knob with index mark at 12 o'clock.
        let knob = NSBezierPath(ovalIn: NSRect(x: 6.4, y: 6.4, width: 5.2, height: 5.2))
        knob.lineWidth = 1.3
        knob.stroke()

        let knobMark = NSBezierPath()
        knobMark.lineWidth = 1.2
        knobMark.lineCapStyle = .round
        knobMark.move(to: NSPoint(x: 9.0, y: 10.6))
        knobMark.line(to: NSPoint(x: 9.0, y: 9.3))
        knobMark.stroke()

        if let badge = badgeColor(for: state) {
            NSGraphicsContext.current?.cgContext.setAlpha(1)
            // Halo keeps the dot readable against the body stroke and
            // against both menu-bar appearances.
            let halo = NSBezierPath(ovalIn: NSRect(x: 10.6, y: 0.2, width: 7.2, height: 7.2))
            (darkMenuBar ? NSColor(white: 0.1, alpha: 1) : .white).setFill()
            halo.fill()
            badge.setFill()
            NSBezierPath(ovalIn: NSRect(x: 11.4, y: 1.0, width: 5.6, height: 5.6)).fill()
        }
    }

    private static func badgeColor(for state: DialStatusBarState) -> NSColor? {
        switch state {
        case .lowBattery: return .systemRed
        case .charging: return .systemGreen
        case .needsPermission: return .systemOrange
        case .disconnected, .normal: return nil
        }
    }
}