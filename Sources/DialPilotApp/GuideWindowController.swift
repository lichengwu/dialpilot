import AppKit
import DialPilotCore

/// Raycast-style full-screen light guide.
///
/// Why a window instead of the old inline strip: expanding a strip inside
/// the popover changed the popover's height, and collapsing it left a
/// stale-height blank gap (reported twice on real hardware). A separate full-screen
/// window has no layout coupling to the popover at all — the bug is gone
/// by construction, and the cards get room to breathe.
///
/// Interaction: ←/→ or swipe to move, click anywhere or Esc to dismiss.
/// Borderless, covers the main screen, dark scrim — same feel as Raycast's
/// first-run / command palette.
final class GuideWindowController: NSWindowController {
    private let pageStack = NSStackView()
    private let dotsView = GuideDotsView()
    private var pageIndex = 0
    private static let states: [DialAgentState] = [
        .idle, .thinking, .working, .attention, .notification, .error, .sweeping,
    ]

    convenience init() {
        // `NSScreen.screens` is never empty while an app is running, but a
        // clamped fallback costs nothing and keeps this init total.
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = GuideWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        self.init(window: window)
        buildUI()
    }

    /// Show centered on the current main screen, reset to first page.
    func present() {
        guard let window, let screen = NSScreen.main else { return }
        window.setFrame(screen.frame, display: true)
        pageIndex = 0
        layoutPages()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Dark scrim over the whole screen.
        let scrim = NSView(frame: content.bounds)
        scrim.autoresizingMask = [.width, .height]
        scrim.wantsLayer = true
        scrim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        content.addSubview(scrim)

        // Title + subtitle.
        let title = NSTextField(labelWithString: L10n.text(.lightGuideTitle))
        title.font = .systemFont(ofSize: 28, weight: .bold)
        title.textColor = .white
        title.alignment = .center
        let subtitle = NSTextField(labelWithString: L10n.text(.guideWindowSubtitle))
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = NSColor.white.withAlphaComponent(0.65)
        subtitle.alignment = .center

        // Card container: one big card centered, swapped on navigation.
        pageStack.orientation = .horizontal
        pageStack.alignment = .centerY
        pageStack.distribution = .fill
        pageStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(pageStack)

        dotsView.numberOfPages = Self.states.count
        dotsView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(dotsView)

        let hint = NSTextField(labelWithString: L10n.text(.guideWindowHint))
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = NSColor.white.withAlphaComponent(0.45)
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(hint)

        title.translatesAutoresizingMaskIntoConstraints = false
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)
        content.addSubview(subtitle)

        let cardWidth: CGFloat = 460
        let cardHeight: CGFloat = 340
        // Title sits at 16% of the screen height — expressed as a ratio of
        // the content height so it stays put when the window is re-framed on
        // a different display, instead of baking in the launch screen.
        let titleTop = NSLayoutConstraint(
            item: title, attribute: .top, relatedBy: .equal,
            toItem: content, attribute: .height, multiplier: 0.16, constant: 0
        )
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            titleTop,
            subtitle.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            pageStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            pageStack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: 10),
            pageStack.widthAnchor.constraint(equalToConstant: cardWidth),
            pageStack.heightAnchor.constraint(equalToConstant: cardHeight),
            dotsView.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            dotsView.topAnchor.constraint(equalTo: pageStack.bottomAnchor, constant: 24),
            dotsView.heightAnchor.constraint(equalToConstant: 10),
            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            hint.topAnchor.constraint(equalTo: dotsView.bottomAnchor, constant: 18),
        ])

        for state in Self.states {
            let card = GuideCardView(state: state)
            card.translatesAutoresizingMaskIntoConstraints = false
            pageStack.addArrangedSubview(card)
            NSLayoutConstraint.activate([
                card.widthAnchor.constraint(equalToConstant: cardWidth),
                card.heightAnchor.constraint(equalToConstant: cardHeight),
            ])
        }
        layoutPages()

        // Click anywhere dismisses — attached to the content view, not the
        // scrim, because the cards and labels sit above the scrim and would
        // otherwise swallow the click. Arrows / trackpad swipe navigate.
        let click = NSClickGestureRecognizer(target: self, action: #selector(dismiss))
        content.addGestureRecognizer(click)
    }

    private func layoutPages() {
        for (i, view) in pageStack.arrangedSubviews.enumerated() {
            view.isHidden = i != pageIndex
        }
        dotsView.currentPage = pageIndex
    }

    @objc private func dismiss() {
        window?.orderOut(nil)
    }

    fileprivate func step(_ delta: Int) {
        let next = pageIndex + delta
        guard next >= 0, next < Self.states.count else { return }
        pageIndex = next
        layoutPages()
    }

    fileprivate func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            dismiss()
            return true
        case 123: // ←
            step(-1)
            return true
        case 124: // →
            step(1)
            return true
        default:
            return false
        }
    }
}

/// Borderless window that can become key (to receive Esc / arrows) and
/// forwards keys to the controller. Trackpad horizontal swipes arrive as
/// scroll events with a horizontal delta; those step pages too.
private final class GuideWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if let controller = windowController as? GuideWindowController,
           controller.handleKey(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // Horizontal swipe (trackpad two-finger left/right) steps pages.
        // Vertical scroll is ignored — there is nothing to scroll.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
           abs(event.scrollingDeltaX) > 2,
           let controller = windowController as? GuideWindowController {
            controller.step(event.scrollingDeltaX < 0 ? 1 : -1)
            return
        }
        super.scrollWheel(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}

/// One large guide card: device diagram left, when/pattern right.
private final class GuideCardView: NSView {
    private let state: DialAgentState

    init(state: DialAgentState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 18
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 1).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        // The card is drawn, not built from text views, so VoiceOver has
        // nothing to read unless we describe it.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(stateName). \(whenText) \(howText)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let accent = stateColor

        // State name + dot.
        accent.setFill()
        NSBezierPath(ovalIn: NSRect(x: 30, y: bounds.height - 44, width: 12, height: 12)).fill()
        drawText(stateName, at: NSPoint(x: 52, y: bounds.height - 48),
                 font: .systemFont(ofSize: 22, weight: .bold), color: .white)

        // Device diagram, large.
        drawDevice(in: NSRect(x: 40, y: 60, width: 130, height: 200), accent: accent)

        // When / Pattern text.
        let textX: CGFloat = 210
        let textWidth = bounds.width - textX - 30
        drawText(L10n.language == .chinese ? "何时亮" : "WHEN",
                 at: NSPoint(x: textX, y: bounds.height - 100),
                 font: .systemFont(ofSize: 12, weight: .semibold),
                 color: NSColor.white.withAlphaComponent(0.5))
        drawWrapped(whenText, at: NSPoint(x: textX, y: bounds.height - 122),
                    width: textWidth, font: .systemFont(ofSize: 16), color: .white, maxLines: 3)
        drawText(L10n.language == .chinese ? "怎么亮" : "PATTERN",
                 at: NSPoint(x: textX, y: bounds.height - 200),
                 font: .systemFont(ofSize: 12, weight: .semibold),
                 color: NSColor.white.withAlphaComponent(0.5))
        drawWrapped(howText, at: NSPoint(x: textX, y: bounds.height - 222),
                    width: textWidth, font: .systemFont(ofSize: 16), color: .white, maxLines: 3)
    }

    private func drawDevice(in rect: NSRect, accent: NSColor) {
        let lit = litLEDs
        let body = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 22)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        body.lineWidth = 2
        body.stroke()

        // Knob (LED 3).
        let knobRect = NSRect(x: rect.midX - 34, y: rect.maxY - 86, width: 68, height: 68)
        let knobLit = lit.contains(3)
        if knobLit {
            accent.withAlphaComponent(0.30).setFill()
            NSBezierPath(ovalIn: knobRect.insetBy(dx: -8, dy: -8)).fill()
        }
        let knob = NSBezierPath(ovalIn: knobRect)
        (knobLit ? accent : NSColor.white.withAlphaComponent(0.4)).setStroke()
        knob.lineWidth = knobLit ? 3.5 : 2
        knob.stroke()
        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: knobRect.midX, y: knobRect.maxY - 6))
        mark.line(to: NSPoint(x: knobRect.midX, y: knobRect.maxY - 20))
        (knobLit ? accent : NSColor.white.withAlphaComponent(0.4)).setStroke()
        mark.lineWidth = 3
        mark.lineCapStyle = .round
        mark.stroke()

        // Three buttons: top (no LED), middle (1), bottom (2).
        for (y, led) in [(rect.maxY - 116, 0), (rect.maxY - 146, 1), (rect.maxY - 176, 2)] as [(CGFloat, Int)] {
            let r = NSRect(x: rect.midX - 22, y: y, width: 44, height: 16)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            if led != 0 && lit.contains(led) {
                accent.setFill()
                path.fill()
            } else {
                NSColor.white.withAlphaComponent(0.3).setStroke()
                path.lineWidth = 1.5
                path.stroke()
            }
        }
    }

    private var litLEDs: Set<Int> {
        switch state {
        case .idle, .sleeping, .off: return []
        case .thinking, .working: return [3]
        case .attention: return [1]
        case .notification: return [1, 2]
        case .error: return [0, 1, 2, 3]
        case .sweeping: return [1]
        }
    }

    private var stateColor: NSColor {
        switch state {
        case .notification: return .systemOrange
        case .error: return .systemRed
        case .working, .thinking, .sweeping: return .systemBlue
        case .attention: return .systemGreen
        case .idle, .sleeping, .off: return NSColor.white.withAlphaComponent(0.5)
        }
    }

    private var stateName: String {
        switch state {
        case .idle: return L10n.text(.stateIdle)
        case .thinking: return L10n.text(.stateThinking)
        case .working: return L10n.text(.stateWorking)
        case .attention: return L10n.text(.stateAttention)
        case .notification: return L10n.text(.stateNotification)
        case .error: return L10n.text(.stateError)
        case .sweeping: return L10n.text(.stateSweeping)
        case .sleeping, .off: return L10n.text(.stateIdle)
        }
    }

    private var whenText: String {
        switch state {
        case .idle: return L10n.text(.guideIdleWhen)
        case .thinking: return L10n.text(.guideThinkingWhen)
        case .working: return L10n.text(.guideWorkingWhen)
        case .attention: return L10n.text(.guideAttentionWhen)
        case .notification: return L10n.text(.guideNotificationWhen)
        case .error: return L10n.text(.guideErrorWhen)
        case .sweeping: return L10n.text(.guideSweepingWhen)
        case .sleeping, .off: return L10n.text(.guideIdleWhen)
        }
    }

    private var howText: String {
        switch state {
        case .idle: return L10n.text(.guideIdleHow)
        case .thinking: return L10n.text(.guideThinkingHow)
        case .working: return L10n.text(.guideWorkingHow)
        case .attention: return L10n.text(.guideAttentionHow)
        case .notification: return L10n.text(.guideNotificationHow)
        case .error: return L10n.text(.guideErrorHow)
        case .sweeping: return L10n.text(.guideSweepingHow)
        case .sleeping, .off: return L10n.text(.guideIdleHow)
        }
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawWrapped(_ text: String, at point: NSPoint, width: CGFloat,
                             font: NSFont, color: NSColor, maxLines: Int) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let lineH = font.pointSize + 6
        let rect = NSRect(x: point.x, y: point.y - CGFloat(maxLines) * lineH,
                          width: width, height: CGFloat(maxLines) * lineH)
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: style,
        ])
    }
}

/// Page indicator dots for the guide window.
private final class GuideDotsView: NSView {
    var numberOfPages: Int = 0 { didSet { needsDisplay = true } }
    var currentPage: Int = 0 { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(numberOfPages) * 10 + CGFloat(max(numberOfPages - 1, 0)) * 8, height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard numberOfPages > 0 else { return }
        let dot: CGFloat = 8
        let spacing: CGFloat = 10
        let total = CGFloat(numberOfPages) * dot + CGFloat(numberOfPages - 1) * spacing
        var x = (bounds.width - total) / 2
        for page in 0..<numberOfPages {
            let rect = NSRect(x: x, y: (bounds.height - dot) / 2, width: dot, height: dot)
            (page == currentPage ? NSColor.white : NSColor.white.withAlphaComponent(0.3)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            x += dot + spacing
        }
    }
}