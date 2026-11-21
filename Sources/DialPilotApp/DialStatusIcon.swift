import AppKit
import DialPilotCore

/// Menu-bar status icon: a line-art AU05 dial with a profile badge.
/// Template image — macOS tints it for light/dark menu bars automatically.
///
/// Design: rounded-rect body, speaker slot, rotary knob with index mark,
/// three button dots. Badge at top-right: sparkle = AI profile,
/// sliders = System profile. Redrawn for DialPilot: cleaner
/// geometry, consistent 1.1pt strokes, badge no longer collides with body.
enum DialStatusIcon {
    static func image(for profile: ProfileID) -> NSImage? {
        let image = NSImage(
            size: NSSize(width: 18, height: 18),
            flipped: false
        ) { _ in
            drawDevice(profile: profile)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DialPilot：\(profile.displayName)"
        return image
    }

    private static func drawDevice(profile: ProfileID) {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        // Body: tall rounded rectangle, left-of-center to leave badge room.
        let body = NSBezierPath(
            roundedRect: NSRect(x: 2.5, y: 1.0, width: 9.0, height: 16.0),
            xRadius: 2.4,
            yRadius: 2.4
        )
        body.lineWidth = 1.2
        body.stroke()

        // Speaker slot near the top.
        let speaker = NSBezierPath()
        speaker.lineWidth = 1.0
        speaker.lineCapStyle = .round
        speaker.move(to: NSPoint(x: 5.2, y: 14.6))
        speaker.line(to: NSPoint(x: 8.8, y: 14.6))
        speaker.stroke()

        // Rotary knob with an index mark at 12 o'clock.
        let knob = NSBezierPath(ovalIn: NSRect(x: 4.3, y: 8.2, width: 5.4, height: 5.4))
        knob.lineWidth = 1.1
        knob.stroke()

        let knobMark = NSBezierPath()
        knobMark.lineWidth = 1.0
        knobMark.lineCapStyle = .round
        knobMark.move(to: NSPoint(x: 7.0, y: 12.6))
        knobMark.line(to: NSPoint(x: 7.0, y: 11.4))
        knobMark.stroke()

        // Three button dots below the knob.
        for y in [6.6, 4.6, 2.6] as [CGFloat] {
            let dot = NSBezierPath(ovalIn: NSRect(x: 6.1, y: y, width: 1.8, height: 1.3))
            dot.fill()
        }

        switch profile {
        case .a:
            drawAIBadge()
        case .b:
            drawSystemBadge()
        }
    }

    /// AI profile: four-point sparkle, kept clear of the body edge.
    private static func drawAIBadge() {
        let sparkle = NSBezierPath()
        sparkle.lineWidth = 1.2
        sparkle.lineCapStyle = .round
        sparkle.move(to: NSPoint(x: 15.0, y: 11.6))
        sparkle.line(to: NSPoint(x: 15.0, y: 16.4))
        sparkle.move(to: NSPoint(x: 12.9, y: 14.0))
        sparkle.line(to: NSPoint(x: 17.1, y: 14.0))
        sparkle.stroke()

        let accent = NSBezierPath()
        accent.lineWidth = 1.0
        accent.lineCapStyle = .round
        accent.move(to: NSPoint(x: 13.1, y: 16.0))
        accent.line(to: NSPoint(x: 13.7, y: 16.6))
        accent.stroke()
    }

    /// System profile: two slider tracks with offset thumbs, clear of body.
    private static func drawSystemBadge() {
        let sliders = NSBezierPath()
        sliders.lineWidth = 1.1
        sliders.lineCapStyle = .round
        sliders.move(to: NSPoint(x: 12.9, y: 15.2))
        sliders.line(to: NSPoint(x: 17.1, y: 15.2))
        sliders.move(to: NSPoint(x: 12.9, y: 12.4))
        sliders.line(to: NSPoint(x: 17.1, y: 12.4))
        sliders.stroke()

        NSBezierPath(ovalIn: NSRect(x: 13.5, y: 14.35, width: 1.7, height: 1.7)).fill()
        NSBezierPath(ovalIn: NSRect(x: 15.2, y: 11.55, width: 1.7, height: 1.7)).fill()
    }
}