import AppKit

/// Fixed metrics for the menu-bar panel. Width is a product decision (the
/// cards are designed for 380pt); height is whatever the content needs.
enum DialPanelMetrics {
    static let width: CGFloat = 380
    static let cornerRadius: CGFloat = 13
    static let arrowHeight: CGFloat = 9
    static let arrowWidth: CGFloat = 18
    /// The arrow tip overlaps the menu bar's bottom edge by this much.
    static let topGap: CGFloat = 2
    static let screenMargin: CGFloat = 6
    static let minContentHeight: CGFloat = 240
}

/// Where the panel window goes, and where its arrow points. Pure value type
/// so the geometry can be unit-tested without a screen or a status item.
struct DialPanelPlacement: Equatable {
    /// Window frame in screen coordinates (bottom-left origin).
    let frame: NSRect
    /// Arrow tip x in window coordinates.
    let arrowCenterX: CGFloat
}

enum DialPanelGeometry {
    /// Places a panel of `contentHeight` under `anchor` (the status item's
    /// screen rect), clamped to `screen` so it never hangs off an edge.
    ///
    /// The invariant this whole file exists for: the window is exactly
    /// `width × (contentHeight + arrowHeight)`. There is no code path that
    /// can produce a window larger than its content, which is what made the
    /// old NSPopover show a full-screen grey rectangle with a 380pt card
    /// stuck in its top-left corner.
    static func placement(
        anchor: NSRect, contentHeight: CGFloat, screen: NSRect
    ) -> DialPanelPlacement {
        let width = DialPanelMetrics.width
        let margin = DialPanelMetrics.screenMargin
        // The arrow tip tucks under the menu bar; the status item's bottom
        // edge *is* the menu bar's bottom edge.
        let top = anchor.minY + DialPanelMetrics.topGap

        // Content taller than the screen gets clipped at the bottom rather
        // than pushing the panel up over the menu bar. The real layout sits
        // around 600pt, so this is a guard, not a layout mode.
        let available = top - (screen.minY + margin) - DialPanelMetrics.arrowHeight
        let content = max(
            min(max(contentHeight, DialPanelMetrics.minContentHeight), available),
            DialPanelMetrics.minContentHeight
        )
        let height = content + DialPanelMetrics.arrowHeight

        let minX = screen.minX + margin
        let maxX = screen.maxX - margin - width
        var x = anchor.midX - width / 2
        x = maxX < minX ? minX : min(max(x, minX), maxX)

        var y = top - height
        let minY = screen.minY + margin
        if y < minY { y = minY }

        // Keep the arrow on the rounded body: pushing it into a corner
        // would poke out of the curve.
        let arrowLimit = DialPanelMetrics.cornerRadius + DialPanelMetrics.arrowWidth / 2
        let lowest = min(arrowLimit, width / 2)
        let highest = max(width - arrowLimit, width / 2)
        let arrowX = min(max(anchor.midX - x, lowest), highest)

        return DialPanelPlacement(
            frame: NSRect(x: x, y: y, width: width, height: height),
            arrowCenterX: arrowX
        )
    }
}

/// Borderless panel that can take key focus (needed for the popup buttons
/// and for Esc), but never becomes the app's main window.
final class DialPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Draws the panel body: a rounded card with an arrow at the top.
final class DialPanelBackgroundView: NSView {
    var arrowCenterX: CGFloat = DialPanelMetrics.width / 2 {
        didSet { if arrowCenterX != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = DialPanelMetrics.cornerRadius
        let arrow = DialPanelMetrics.arrowHeight
        let body = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - arrow)

        let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
        let tip = NSBezierPath()
        let half = DialPanelMetrics.arrowWidth / 2
        tip.move(to: NSPoint(x: arrowCenterX - half, y: body.maxY - 0.5))
        tip.line(to: NSPoint(x: arrowCenterX, y: body.maxY + arrow))
        tip.line(to: NSPoint(x: arrowCenterX + half, y: body.maxY - 0.5))
        tip.close()
        path.append(tip)

        NSColor.windowBackgroundColor.setFill()
        path.fill()

        // Hairline so the card reads as a surface over any wallpaper.
        NSColor.separatorColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Owns the menu-bar panel window.
///
/// Why not `NSPopover`: the popover decides both its own size and its
/// own position from the anchor view, and neither is recoverable once the
/// menu bar rearranges. On a machine running a menu-bar manager that moves
/// and hides status items, the popover window came back as a ~1900×580
/// grey field with the 380pt card pinned to its top-left corner — blank
/// space everywhere, and it drifted away from the icon it belongs to.
///
/// So the window is ours: we set the frame to exactly
/// `content + arrow` on every layout, and re-derive the anchor from the
/// status button's *live* screen rect instead of a cached one. Whenever the
/// icon moves, the panel moves with it; if the icon is gone, the panel
/// closes instead of floating detached.
final class DialPanelController: NSWindowController {
    private let content: SettingsViewController
    private let background = DialPanelBackgroundView()
    private let statusButton: () -> NSStatusBarButton?
    private var contentHeight: CGFloat = 0
    private var lastPlacement: DialPanelPlacement?
    private var monitors: [Any] = []
    private var dismissObservers: [NSObjectProtocol] = []
    private var anchorObservers: [NSObjectProtocol] = []
    private var isShown = false
    private var presentRetryScheduled = false
    /// Anchor captured at show time. Used when the live rect is unusable
    /// (item stashed by a menu-bar manager) so the panel holds still.
    private var pinnedAnchor: NSRect?
    private var shownAt = Date.distantPast

    /// Called after the panel becomes visible / after it closes — the app
    /// flips its power-poll cadence here.
    var onShow: (() -> Void)?
    var onClose: (() -> Void)?

    var isVisible: Bool { isShown }

    init(content: SettingsViewController, statusButton: @escaping () -> NSStatusBarButton?) {
        self.content = content
        self.statusButton = statusButton
        let window = DialPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: DialPanelMetrics.width, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        super.init(window: window)
        window.contentView = background
        background.addSubview(content.view)
        content.onContentSizeChanged = { [weak self] size in
            guard let self else { return }
            self.contentHeight = size.height
            self.repositionIfNeeded()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Show / hide

    func toggle() {
        if isShown { dismiss(reason: "toggle") } else { present() }
    }

    func present() {
        guard !isShown else { return }
        guard let anchor = liveAnchorRect() ?? pointerAnchor() else {
            // The status item's button has no window for the first runloop
            // turn after launch, and a menu-bar manager can briefly detach
            // it while rearranging. One short retry, then give up.
            guard !presentRetryScheduled else { return }
            presentRetryScheduled = true
            DebugLog.log(
                "panel: no anchor button=\(String(describing: statusButton()?.frame)) "
                    + "window=\(String(describing: statusButton()?.window?.frame))"
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.presentRetryScheduled = false
                self?.present()
            }
            return
        }
        // Pinned for the lifetime of this presentation: when the anchor
        // came from the pointer, chasing the pointer would make the panel
        // jitter as soon as the user moved the mouse.
        pinnedAnchor = anchor
        contentHeight = content.measuredContentSize().height
        applyPlacement(anchor: anchor)
        window?.alphaValue = 1
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isShown = true
        shownAt = Date()
        installMonitors()
        observeAnchorWindow()
        DebugLog.log(
            "panel: show anchor=\(anchor) frame=\(String(describing: window?.frame)) content=\(contentHeight)"
        )
        onShow?()
    }

    func dismiss(reason: String = #function) {
        guard isShown else { return }
        isShown = false
        pinnedAnchor = nil
        DebugLog.log("panel: hide reason=\(reason)")
        removeMonitors()
        window?.orderOut(nil)
        onClose?()
    }

    // MARK: - Geometry

    /// Re-derives the anchor from the button's current screen rect. Cheap
    /// enough to call on every UI refresh (the heartbeat already runs at
    /// ~0.8 s), which is what keeps the panel glued to an icon that a
    /// menu-bar manager just shoved sideways.
    func repositionIfNeeded() {
        guard isShown else { return }
        guard let anchor = liveAnchorRect() ?? pinnedAnchor,
              let screen = screen(for: anchor) else {
            // The item is hidden or off-screen — a panel pointing at
            // nothing is worse than no panel.
            dismiss(reason: "anchor-lost")
            return
        }
        let placement = DialPanelGeometry.placement(
            anchor: anchor, contentHeight: contentHeight, screen: screen.visibleFrame
        )
        guard placement != lastPlacement else { return }
        apply(placement)
    }

    private func applyPlacement(anchor: NSRect) {
        guard let screen = screen(for: anchor) else {
            // Every Mac has at least one screen; this only guards against a
            // status item reporting a rect while the display list is mid-
            // rebuild (clamshell hot-plug). Keep the panel where it is.
            DebugLog.log("panel: no screen for anchor=\(anchor)")
            return
        }
        apply(
            DialPanelGeometry.placement(
                anchor: anchor, contentHeight: contentHeight, screen: screen.visibleFrame
            )
        )
    }

    private func apply(_ placement: DialPanelPlacement) {
        lastPlacement = placement
        background.arrowCenterX = placement.arrowCenterX
        let bodyHeight = placement.frame.height - DialPanelMetrics.arrowHeight
        content.view.frame = NSRect(
            x: 0, y: 0, width: DialPanelMetrics.width, height: bodyHeight
        )
        content.view.layoutSubtreeIfNeeded()
        // The content view follows the window automatically; setting its
        // frame here would just fight AppKit.
        window?.setFrame(placement.frame, display: true)
    }

    /// The status item's real screen rect — but only if it is actually in a
    /// menu bar. Menu-bar managers (Bartender, Ice) keep the *real* item in
    /// an off-screen window at the screen corner and draw a proxy in the
    /// bar; measured on this machine, the button reported
    /// `(0, -11, 34, 22)` while the user was clicking a proxy at x≈1285.
    /// Anchoring a window there is how the old popover ended up as a huge
    /// grey field in the corner.
    private func liveAnchorRect() -> NSRect? {
        guard let button = statusButton(), let anchorWindow = button.window else { return nil }
        let rect = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard rect.width > 0, rect.height > 0 else { return nil }
        guard NSScreen.screens.contains(where: { isInMenuBar(rect, of: $0) }) else { return nil }
        return rect
    }

    private func isInMenuBar(_ rect: NSRect, of screen: NSScreen) -> Bool {
        // A status item sits between the menu bar's bottom edge and the top
        // of the screen. ±8pt absorbs the shadow/rounding at both ends.
        let bottom = screen.visibleFrame.maxY
        let top = screen.frame.maxY
        return rect.midY >= bottom - 8 && rect.midY <= top + 8
    }

    /// Fallback when the item has been stashed by a menu-bar manager: the
    /// only honest answer to "where did the user click" is the pointer. The
    /// y comes from the menu bar, not the pointer, so the panel still hangs
    /// from the bar instead of floating mid-air.
    private func pointerAnchor() -> NSRect? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else {
            return nil
        }
        let barBottom = screen.visibleFrame.maxY
        guard mouse.y >= barBottom - 40 else { return nil }
        return NSRect(x: mouse.x - 12, y: barBottom, width: 24, height: 22)
    }

    private func screen(for anchor: NSRect) -> NSScreen? {
        let point = NSPoint(x: anchor.midX, y: anchor.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.intersects(anchor) }
            ?? NSScreen.main
    }

    /// A menu-bar manager can move the item by moving the status bar's
    /// window; the notification fires there, not on the button.
    private func observeAnchorWindow() {
        removeAnchorObservers()
        guard let anchorWindow = statusButton()?.window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            anchorObservers.append(
                center.addObserver(forName: name, object: anchorWindow, queue: .main) { [weak self] _ in
                    self?.repositionIfNeeded()
                }
            )
        }
        anchorObservers.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.repositionIfNeeded()
            }
        )
    }

    private func removeAnchorObservers() {
        anchorObservers.forEach(NotificationCenter.default.removeObserver)
        anchorObservers.removeAll()
    }

    // MARK: - Dismissal

    private func installMonitors() {
        removeMonitors()
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }  // Esc
            self.dismiss(reason: "esc")
            return nil
        }) {
            monitors.append(monitor)
        }
        // Clicks inside the panel go to us, so a global monitor only ever
        // sees clicks that landed somewhere else. Clicks on *our* icon are
        // excluded — the button's own action toggles, and a menu-bar
        // manager's proxy icon would otherwise close the panel a moment
        // before the toggle reopens it. Any other click, including another
        // app's menu-bar item, dismisses.
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
                guard let self else { return }
                guard !self.isOwnIconClick(NSEvent.mouseLocation) else { return }
                self.dismiss(reason: "click-outside")
            }
        ) {
            monitors.append(monitor)
        }
        // Cmd-Tab away should drop the panel, but activation right after
        // launch bounces (active → inactive within ~60 ms) and used to close
        // the panel the instant it opened. Only honour it once the panel has
        // actually been up for a moment.
        let resign = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, Date().timeIntervalSince(self.shownAt) > 0.4 else { return }
            self.dismiss(reason: "resign-active")
        }
        dismissObservers.append(resign)
    }

    private func isOwnIconClick(_ location: NSPoint) -> Bool {
        guard NSScreen.screens.contains(where: { screen in
            screen.frame.contains(location) && location.y >= screen.visibleFrame.maxY - 4
        }) else { return false }
        guard let anchor = pinnedAnchor ?? liveAnchorRect() else { return false }
        return abs(location.x - anchor.midX) <= 30
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        dismissObservers.forEach(NotificationCenter.default.removeObserver)
        dismissObservers.removeAll()
        removeAnchorObservers()
    }
}
