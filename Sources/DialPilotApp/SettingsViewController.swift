import AppKit
import DialPilotCore

/// Menu-bar panel: card-grouped, gauge-led, zero maintenance buttons.
/// Hosted by `DialPanelController`, which owns the window and sizes it to
/// `measuredContentSize()` — this controller never resizes a window.
///
/// Visual language borrowed from iStat Menus: related controls live in
/// rounded cards on a subtle surface; the battery is a ring gauge with a
/// big number instead of a dot+percent pair; usage stats get a quiet
/// 7-day bar chart. Status color is reserved for semantics (green ok /
/// orange warn / red danger), everything else stays neutral.
///
/// Structure: header → notice (events only) → permission banner (only
/// when missing) → device card (battery ring + status) → keys card →
/// lights card → usage card → footer. Height fits content; the light
/// guide is a separate full-screen window, so nothing here ever changes
/// size because of it.
final class SettingsViewController: NSViewController {
    var onMappingChanged: ((ProfileID, InputControl, ControlBinding) -> Void)?
    var onQuit: (() -> Void)?
    var onShowAgentHooks: (() -> Void)?
    var onPreviewLedState: ((DialAgentState?) -> Void)?
    var onLightModeChanged: ((DialLightMode) -> Void)?
    var onGrantAccessibility: (() -> Void)?
    var onGrantInputMonitoring: (() -> Void)?
    var onQuitVendor: (() -> Void)?
    var onShowGuide: (() -> Void)?
    /// The natural content size changed. The panel host owns the window and
    /// resizes it to exactly this height — the view controller never sizes
    /// a window itself.
    var onContentSizeChanged: ((NSSize) -> Void)?
    var currentLedState: DialAgentState = .idle {
        didSet { if isViewLoaded { reloadLedChip() } }
    }

    private var configuration: AppConfiguration
    private var listenerActive = false
    private var accessibilityGranted = false
    private var inputMonitoringGranted = false
    private var deviceConnected = false
    private var deviceResponsive = true
    private var vendorRunning = false
    private var powerStatus = DialPowerSnapshot()
    private var powerSaving = false
    private var hardwareSyncInProgress = false
    private var notice: String?
    private var usageStats = DialUsageStats()

    private let batteryRing = BatteryRingView()
    private let connectionDot = NSView()
    private let connectionLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let ledChip = NSTextField(labelWithString: "")
    /// "who is on the LEDs" — winning agent + active session count.
    /// Hover lists every active session (agent · state · age).
    private let sessionSourceLabel = NSTextField(labelWithString: "")
    private var activeSessions: [DialLedSessionAggregator.SessionInfo] = []
    private let ledPreviewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lightModeSelector = NSSegmentedControl(
        labels: DialLightMode.allCases.map(\.displayName),
        trackingMode: .selectOne, target: nil, action: nil
    )
    private lazy var guideButton = NSButton(
        title: L10n.text(.lightGuideTitle), target: self, action: #selector(showGuide(_:))
    )
    private var actionPopups: [InputControl: NSPopUpButton] = [:]
    private let recordShortcutToken = "__record_native_shortcut__"

    private let usageTodayValue = NSTextField(labelWithString: "0")
    private let usageTotalValue = NSTextField(labelWithString: "0")
    private let usageTopValue = NSTextField(labelWithString: "")
    private let usageChart = UsageBarChartView()
    private let usageCard = NSStackView()

    private let permissionBanner = NSStackView()
    private let studioBanner = NSStackView()
    private lazy var quitStudioButton = NSButton(
        title: L10n.text(.quitStudio), target: self, action: #selector(quitStudio(_:))
    )
    private lazy var grantAXButton = NSButton(
        title: L10n.text(.grantAccessibility), target: self, action: #selector(grantAccessibility(_:))
    )
    private lazy var grantIMButton = NSButton(
        title: L10n.text(.grantInputMonitoring), target: self, action: #selector(grantInputMonitoring(_:))
    )

    private static let previewStates: [DialAgentState] = [
        .idle, .thinking, .working, .attention, .notification, .error, .sweeping,
    ]

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))

        let title = NSTextField(labelWithString: "DialPilot")
        title.font = PanelTheme.titleFont
        let quitButton = NSButton(title: L10n.text(.quit), target: self, action: #selector(quit(_:)))
        quitButton.bezelStyle = .inline
        quitButton.controlSize = .small
        quitButton.contentTintColor = .secondaryLabelColor
        let header = NSStackView(views: [title, NSView(), quitButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        // Notice line: hidden unless something happened.
        statusLabel.font = PanelTheme.captionFont
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.isHidden = true

        buildPermissionBanner()
        buildStudioBanner()

        let deviceCard = makeDeviceCard()
        let keysCard = makeKeysCard()
        let lightsCard = makeLightsCard()
        buildUsageCard()

        let stack = NSStackView(views: [
            header,
            statusLabel,
            permissionBanner,
            studioBanner,
            deviceCard,
            keysCard,
            lightsCard,
            usageCard,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        var constraints = [
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            permissionBanner.widthAnchor.constraint(equalTo: stack.widthAnchor),
            studioBanner.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ]
        for card in [deviceCard, keysCard, lightsCard, usageCard] {
            constraints.append(card.widthAnchor.constraint(equalTo: stack.widthAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        reloadControls()
        resizePanelToFit()
    }

    /// Card container: rounded surface + inner vertical stack with padding.
    private func makeCard(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let card = NSStackView(views: views)
        card.orientation = .vertical
        card.alignment = .leading
        card.spacing = spacing
        card.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.07).cgColor
        for v in views where v is NSStackView || v is NSGridView {
            v.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -24).isActive = true
        }
        return card
    }

    // MARK: - Device card

    private func makeDeviceCard() -> NSStackView {
        connectionDot.wantsLayer = true
        connectionDot.layer?.cornerRadius = 4
        connectionDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            connectionDot.widthAnchor.constraint(equalToConstant: 8),
            connectionDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        connectionLabel.font = PanelTheme.bodyFont
        connectionLabel.textColor = .labelColor
        let statusRow = NSStackView(views: [connectionDot, connectionLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 6

        let sectionTitle = PanelTheme.sectionLabel(L10n.text(.deviceSection))
        let textColumn = NSStackView(views: [sectionTitle, statusRow])
        textColumn.orientation = .vertical
        textColumn.alignment = .leading
        textColumn.spacing = 6

        let row = NSStackView(views: [batteryRing, textColumn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        return makeCard([row])
    }

    // MARK: - Keys card

    private func makeKeysCard() -> NSStackView {
        let header = PanelTheme.sectionLabel(L10n.text(.profileSection))
        let grid = makeMappingGrid()
        return makeCard([header, grid], spacing: 6)
    }

    // MARK: - Lights card

    private func makeLightsCard() -> NSStackView {
        lightModeSelector.target = self
        lightModeSelector.action = #selector(lightModeChanged(_:))
        lightModeSelector.controlSize = .small
        guideButton.bezelStyle = .inline
        guideButton.controlSize = .small
        guideButton.font = PanelTheme.captionFont
        let modeRow = NSStackView(views: [
            PanelTheme.sectionLabel(L10n.text(.lightSection)), lightModeSelector,
            NSView(), guideButton,
        ])
        modeRow.orientation = .horizontal
        modeRow.alignment = .centerY
        modeRow.spacing = 10

        ledChip.identifier = NSUserInterfaceItemIdentifier("ledChip")
        ledChip.font = PanelTheme.monoFont
        // The state token must never be clipped or ellipsized — in English
        // "Working" is wide enough that a single row with the preview popup
        // and Connect button squeezed it to "Wo…". It gets its own row.
        ledChip.lineBreakMode = .byClipping
        ledChip.setContentCompressionResistancePriority(.required, for: .horizontal)
        sessionSourceLabel.font = PanelTheme.captionFont
        sessionSourceLabel.textColor = .secondaryLabelColor
        sessionSourceLabel.lineBreakMode = .byTruncatingTail
        // Hard width cap: the label truncates instead of pushing the row
        // (and the whole panel) wider. Full detail stays in the tooltip.
        sessionSourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 110).isActive = true
        sessionSourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sessionSourceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rebuildPreviewPopup()
        ledPreviewPopup.target = self
        ledPreviewPopup.action = #selector(ledPreviewChanged(_:))
        ledPreviewPopup.controlSize = .small
        ledPreviewPopup.toolTip = L10n.text(.lightPreviewHint)
        let hooksButton = NSButton(
            title: L10n.text(.connectAgent), target: self, action: #selector(showAgentHooks(_:))
        )
        hooksButton.bezelStyle = .rounded
        hooksButton.controlSize = .small

        // Three rows instead of two. Row 2 answers "what is lit and who owns
        // it"; row 3 holds the two wide controls. At 380pt the old combined
        // row needed ~360pt of intrinsic width inside a 328pt content area,
        // so AppKit stole the width from the state chip.
        let stateRow = NSStackView(views: [ledChip, sessionSourceLabel, NSView()])
        stateRow.orientation = .horizontal
        stateRow.alignment = .centerY
        stateRow.spacing = 8

        let actionsRow = NSStackView(views: [ledPreviewPopup, hooksButton, NSView()])
        actionsRow.orientation = .horizontal
        actionsRow.alignment = .centerY
        actionsRow.spacing = 8

        return makeCard([modeRow, stateRow, actionsRow])
    }

    // MARK: - Usage card

    private func buildUsageCard() {
        for value in [usageTodayValue, usageTotalValue] {
            value.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
            value.textColor = .labelColor
        }
        usageTopValue.font = PanelTheme.bodyFont
        usageTopValue.textColor = .labelColor
        usageTopValue.lineBreakMode = .byTruncatingTail
        usageTopValue.widthAnchor.constraint(lessThanOrEqualToConstant: 130).isActive = true

        let todayColumn = metricColumn(value: usageTodayValue, caption: L10n.text(.usageToday))
        let totalColumn = metricColumn(value: usageTotalValue, caption: L10n.text(.usageTotal))
        let topColumn = metricColumn(value: usageTopValue, caption: L10n.text(.usageTop))
        topColumn.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true

        let metricsRow = NSStackView(views: [todayColumn, totalColumn, NSView(), topColumn])
        metricsRow.orientation = .horizontal
        metricsRow.alignment = .bottom
        metricsRow.spacing = 18

        usageCard.orientation = .vertical
        usageCard.alignment = .leading
        usageCard.spacing = 8
        usageCard.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        usageCard.wantsLayer = true
        usageCard.layer?.cornerRadius = 10
        usageCard.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.07).cgColor
        usageCard.addArrangedSubview(PanelTheme.sectionLabel(L10n.text(.usageTitle)))
        usageCard.addArrangedSubview(metricsRow)
        usageCard.addArrangedSubview(usageChart)
        metricsRow.widthAnchor.constraint(equalTo: usageCard.widthAnchor, constant: -24).isActive = true
        usageChart.widthAnchor.constraint(equalTo: usageCard.widthAnchor, constant: -24).isActive = true
    }

    private func metricColumn(value: NSTextField, caption: String) -> NSStackView {
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = PanelTheme.captionFont
        captionLabel.textColor = .secondaryLabelColor
        let column = NSStackView(views: [value, captionLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 1
        return column
    }

    private func buildPermissionBanner() {
        permissionBanner.orientation = .vertical
        permissionBanner.alignment = .leading
        permissionBanner.spacing = 6
        permissionBanner.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        permissionBanner.wantsLayer = true
        permissionBanner.layer?.cornerRadius = 8
        permissionBanner.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.10).cgColor
        let title = NSTextField(labelWithString: L10n.text(.permissionTitle))
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .systemOrange
        grantAXButton.bezelStyle = .rounded
        grantAXButton.controlSize = .small
        grantIMButton.bezelStyle = .rounded
        grantIMButton.controlSize = .small
        let buttons = NSStackView(views: [grantAXButton, grantIMButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        permissionBanner.addArrangedSubview(title)
        permissionBanner.addArrangedSubview(buttons)
        permissionBanner.isHidden = true
    }

    /// Same severity as the permission banner: while Ulanzi Studio runs,
    /// DialPilot cannot own the dial at all. One click quits it; recovery is
    /// automatic (AppDelegate.reconcileVendorPresence).
    private func buildStudioBanner() {
        studioBanner.orientation = .vertical
        studioBanner.alignment = .leading
        studioBanner.spacing = 6
        studioBanner.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        studioBanner.wantsLayer = true
        studioBanner.layer?.cornerRadius = 8
        studioBanner.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.10).cgColor
        let title = NSTextField(labelWithString: L10n.text(.studioBannerTitle))
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .systemOrange
        let body = NSTextField(wrappingLabelWithString: L10n.text(.studioBannerBody))
        body.font = PanelTheme.captionFont
        body.textColor = .secondaryLabelColor
        body.maximumNumberOfLines = 2
        quitStudioButton.bezelStyle = .rounded
        quitStudioButton.controlSize = .small
        quitStudioButton.identifier = NSUserInterfaceItemIdentifier("quitStudioButton")
        quitStudioButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        studioBanner.addArrangedSubview(title)
        studioBanner.addArrangedSubview(body)
        studioBanner.addArrangedSubview(quitStudioButton)
        studioBanner.isHidden = true
    }

    // MARK: - Update

    func update(
        configuration: AppConfiguration,
        listenerActive: Bool,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        deviceConnected: Bool,
        deviceResponsive: Bool = true,
        vendorRunning: Bool = false,
        powerStatus: DialPowerSnapshot,
        powerSaving: Bool,
        hardwareSyncInProgress: Bool,
        notice: String?,
        usageStats: DialUsageStats = DialUsageStats(),
        activeSessions: [DialLedSessionAggregator.SessionInfo] = []
    ) {
        self.configuration = configuration
        self.listenerActive = listenerActive
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.deviceConnected = deviceConnected
        self.deviceResponsive = deviceResponsive
        self.vendorRunning = vendorRunning
        self.powerStatus = powerStatus
        self.powerSaving = powerSaving
        self.hardwareSyncInProgress = hardwareSyncInProgress
        self.notice = notice
        self.usageStats = usageStats
        self.activeSessions = activeSessions
        if isViewLoaded {
            reloadControls()
            resizePanelToFit()
        }
    }

    // MARK: - Mapping grid

    private func makeMappingGrid() -> NSGridView {
        let rows: [[NSView]] = InputControl.allCases.map { control in
            let label = NSTextField(labelWithString: control.displayName)
            label.font = PanelTheme.bodyFont
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.identifier = NSUserInterfaceItemIdentifier(control.rawValue)
            popup.target = self
            popup.action = #selector(mappingChanged(_:))
            popup.controlSize = .small
            popup.font = PanelTheme.bodyFont

            popup.removeAllItems()
            for (categoryIndex, category) in KeyActionCategory.allCases.enumerated() {
                if categoryIndex > 0 { popup.menu?.addItem(.separator()) }
                let heading = NSMenuItem(title: category.displayName, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                popup.menu?.addItem(heading)
                for action in KeyAction.allCases where action.category == category {
                    let supported = action.isAppOnly
                        || PresetNativeShortcutResolver.resolve(action) != .unsupported
                    let title = supported
                        ? action.displayName
                        : action.displayName + L10n.text(.offlineUnsupported)
                    popup.addItem(withTitle: title)
                    popup.lastItem?.representedObject = action.rawValue
                    popup.lastItem?.isEnabled = supported
                }
            }
            popup.menu?.addItem(.separator())
            let recordItem = NSMenuItem(title: L10n.text(.recordShortcut), action: nil, keyEquivalent: "")
            recordItem.representedObject = recordShortcutToken
            popup.menu?.addItem(recordItem)
            // Fixed popup width: the intrinsic width follows the longest
            // menu item (267pt), which blows the card budget. 180pt shows
            // every selected action name; the open menu is full-width.
            popup.widthAnchor.constraint(equalToConstant: 180).isActive = true
            // The intrinsic width follows the longest menu item (267pt for
            // "Voice input (hold to talk…)"). Cap it: the closed button only
            // needs to show the selected action; the menu itself opens at
            // full width regardless.
            popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            actionPopups[control] = popup
            return [label, popup]
        }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 3
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    private func rebuildPreviewPopup() {
        ledPreviewPopup.removeAllItems()
        ledPreviewPopup.addItem(withTitle: L10n.text(.previewLive))
        ledPreviewPopup.lastItem?.representedObject = "live"
        for state in Self.previewStates {
            ledPreviewPopup.addItem(withTitle: L10n.text(.previewPrefix) + Self.stateDisplayName(state))
            ledPreviewPopup.lastItem?.representedObject = state.rawValue
        }
    }

    // MARK: - Reload

    private func reloadControls() {
        lightModeSelector.selectedSegment = DialLightMode.allCases.firstIndex(of: configuration.lightMode) ?? 2
        lightModeSelector.toolTip = configuration.lightMode.hint
        let smartActive = configuration.lightMode == .smart && deviceConnected && listenerActive
        ledPreviewPopup.isEnabled = smartActive
        ledChip.isHidden = configuration.lightMode != .smart
        guideButton.isHidden = configuration.lightMode != .smart

        let profile = configuration.activeProfile
        for control in InputControl.allCases {
            let binding = configuration[profile][control]
            let popup = actionPopups[control]
            let matchingItem: NSMenuItem?
            switch binding {
            case let .preset(action):
                matchingItem = popup?.itemArray.first {
                    ($0.representedObject as? String) == action.rawValue
                }
                popup?.itemArray.first {
                    ($0.representedObject as? String) == recordShortcutToken
                }?.title = L10n.text(.recordShortcut)
            case let .shortcut(shortcut):
                matchingItem = popup?.itemArray.first {
                    ($0.representedObject as? String) == recordShortcutToken
                }
                matchingItem?.title = L10n.text(.customShortcut) + shortcut.displayName
            }
            popup?.select(matchingItem)
            popup?.isEnabled = !hardwareSyncInProgress
        }

        reloadDeviceCard()
        reloadNotice()
        reloadLedChip()
        reloadPermissionBanner()
        reloadStudioBanner()
        reloadUsageCard()
    }

    /// Device card: battery ring (big number) + connection status row.
    private func reloadDeviceCard() {
        if let battery = powerStatus.battery {
            batteryRing.percent = Int(battery.percent)
            if battery.isCharging || battery.isFullyCharged || battery.percent >= 50 {
                batteryRing.ringColor = PanelTheme.ok
            } else if battery.percent >= 20 {
                batteryRing.ringColor = PanelTheme.warn
            } else {
                batteryRing.ringColor = PanelTheme.danger
            }
            batteryRing.caption = battery.isCharging ? L10n.text(.charging)
                : battery.isFullyCharged ? L10n.text(.fullyCharged) : L10n.text(.battery)
            batteryRing.toolTip = "\(batteryRing.caption) \(battery.percent)%"
        } else {
            batteryRing.percent = nil
            batteryRing.ringColor = .secondaryLabelColor
            batteryRing.caption = L10n.text(.battery)
            batteryRing.toolTip = nil
        }

        let color: NSColor
        let detail: String
        if !deviceConnected {
            color = .secondaryLabelColor
            detail = L10n.text(.waitingDevice)
        } else if !deviceResponsive {
            // Enumerated on USB but silent: the knob is switched off. Saying
            // "gestures active" here is exactly the lie the user caught.
            color = .secondaryLabelColor
            detail = L10n.text(.deviceNotResponding)
        } else if !accessibilityGranted || !inputMonitoringGranted {
            color = PanelTheme.warn
            detail = !accessibilityGranted ? L10n.text(.needAccessibility) : L10n.text(.needInputMonitoring)
        } else if !listenerActive {
            color = PanelTheme.warn
            detail = L10n.text(.needInputMonitoring)
        } else if powerSaving {
            color = .secondaryLabelColor
            detail = L10n.text(.powerSaving)
        } else {
            color = PanelTheme.ok
            detail = L10n.text(.connectedGestures)
        }
        connectionDot.layer?.backgroundColor = color.cgColor
        connectionLabel.stringValue = detail
        connectionLabel.toolTip = detail
        connectionDot.toolTip = detail
    }

    /// Notice line shows only real events; idle state is conveyed by dots.
    private func reloadNotice() {
        if let notice {
            statusLabel.isHidden = false
            statusLabel.stringValue = notice
            let wrotePrefixes = [
                L10n.text(.noticeWrote), L10n.text(.noticeWroteAppOnly),
                L10n.text(.noticeWroteMarkerSaveFailed),
            ]
            let isWrote = wrotePrefixes.contains { notice.contains($0) }
            statusLabel.textColor = isWrote ? PanelTheme.ok : .labelColor
        } else {
            statusLabel.isHidden = true
        }
    }

    private func reloadPermissionBanner() {
        let missingAX = !accessibilityGranted
        let missingIM = !inputMonitoringGranted
        permissionBanner.isHidden = !missingAX && !missingIM
        grantAXButton.isHidden = !missingAX
        grantIMButton.isHidden = !missingIM
    }

    private func reloadStudioBanner() {
        studioBanner.isHidden = !vendorRunning
        quitStudioButton.isEnabled = !hardwareSyncInProgress
        // The banner carries the full story; the notice line would only
        // repeat it in two different wordings.
        if vendorRunning, notice == L10n.text(.noticeStudioRunning) {
            statusLabel.isHidden = true
        }
    }

    private func reloadLedChip() {
        ledChip.stringValue = "● " + Self.stateDisplayName(currentLedState)
        ledChip.textColor = Self.stateColor(currentLedState)
        reloadSessionSource()
    }

    /// The single LED state comes from multi-session arbitration; this row
    /// makes the winner visible ("CodeBuddy · 3 sessions") and the hover
    /// lists everyone else, so the light is never a mystery.
    private func reloadSessionSource() {
        guard configuration.lightMode == .smart, !activeSessions.isEmpty else {
            sessionSourceLabel.isHidden = true
            sessionSourceLabel.toolTip = nil
            return
        }
        sessionSourceLabel.isHidden = false
        let winner = activeSessions.first { $0.isWinning }
        let winnerName = winner.flatMap { Self.agentDisplayName($0.agent) } ?? L10n.text(.sessionsManual)
        if activeSessions.count > 1 {
            sessionSourceLabel.stringValue = winnerName + " · \(activeSessions.count)" + L10n.text(.sessionsActiveSuffix)
        } else {
            sessionSourceLabel.stringValue = winnerName
        }
        // Hover detail: every active session, winner marked.
        let lines = activeSessions.map { info -> String in
            let name = Self.agentDisplayName(info.agent) ?? info.id
            let mark = info.isWinning ? "◉ " : "○ "
            let age = info.ageSeconds < 60
                ? "\(Int(info.ageSeconds))" + L10n.text(.sessionsAgoSeconds)
                : "\(Int(info.ageSeconds / 60))" + L10n.text(.sessionsAgoMinutes)
            return mark + name + " · " + Self.stateDisplayName(info.state) + " · " + age
        }
        sessionSourceLabel.toolTip = lines.joined(separator: "\n")
        ledChip.toolTip = sessionSourceLabel.toolTip
    }

    static func agentDisplayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        return DialAgentTarget(rawValue: raw)?.displayName ?? raw
    }

    /// Usage card: today / lifetime / top control + 7-day chart. Hidden
    /// entirely until the first recorded event — an all-zero card is noise.
    private func reloadUsageCard() {
        let today = DialUsageStats.dayKey(for: Date())
        usageCard.isHidden = usageStats.lifetimeTotal == 0
        guard !usageCard.isHidden else { return }
        usageTodayValue.stringValue = "\(usageStats.count(onDay: today))"
        usageTotalValue.stringValue = "\(usageStats.lifetimeTotal)"
        usageTopValue.stringValue = usageStats.topControl?.displayName ?? L10n.text(.usageNone)
        let window = usageStats.recentDays(7, today: today)
        usageChart.days = window.enumerated().map { index, entry in
            UsageBarChartView.Day(
                label: String(entry.day.suffix(2)),
                count: entry.count,
                isToday: index == window.count - 1,
                fullDate: entry.day,
                topControlName: usageStats.topControl(onDay: entry.day)?.displayName
            )
        }
        usageTodayValue.toolTip = L10n.text(.usageToday) + ": " + today
        if let top = usageStats.topControl {
            usageTopValue.toolTip = L10n.text(.usageTop) + ": " + top.displayName
                + " · \(usageStats.count(for: top))" + L10n.text(.usageTimesSuffix)
        }
    }

    static func stateDisplayName(_ state: DialAgentState) -> String {
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

    static func stateColor(_ state: DialAgentState) -> NSColor {
        switch state {
        case .notification: return PanelTheme.warn
        case .error: return PanelTheme.danger
        case .working, .thinking, .sweeping: return PanelTheme.accent
        case .attention: return PanelTheme.ok
        case .idle, .sleeping, .off: return .secondaryLabelColor
        }
    }

    // MARK: - Layout

    /// Size the panel to the stack's natural content height — no blank
    /// areas. Width is FIXED at 380: dynamic labels (session source, top
    /// control) must truncate, never stretch the panel. Letting fittingSize
    /// drive width made the panel grow to 522pt when sessions appeared and
    /// never shrink back, leaving a dead band on the right (user screenshot
    /// 2026-11-21).
    ///
    /// Measurement never touches the view's height: `fittingSize` ignores
    /// it, and the old 2000pt probe frame could get committed to a live
    /// window, which is one way the panel ended up as a giant empty field.
    func measuredContentSize() -> NSSize {
        guard let stack = view.subviews.first as? NSStackView else {
            return NSSize(width: DialPanelMetrics.width, height: DialPanelMetrics.minContentHeight)
        }
        if abs(view.frame.width - DialPanelMetrics.width) > 0.5 {
            view.frame.size.width = DialPanelMetrics.width
        }
        stack.layoutSubtreeIfNeeded()
        // 24 = 12pt top inset + 12pt bottom inset.
        let height = max(stack.fittingSize.height + 24, DialPanelMetrics.minContentHeight)
        return NSSize(width: DialPanelMetrics.width, height: height)
    }

    private func resizePanelToFit() {
        let size = measuredContentSize()
        preferredContentSize = size
        view.frame.size = size
        view.subviews.first?.layoutSubtreeIfNeeded()
        onContentSizeChanged?(size)
    }

    // MARK: - Actions

    @objc private func lightModeChanged(_ sender: NSSegmentedControl) {
        let modes = DialLightMode.allCases
        guard sender.selectedSegment >= 0, sender.selectedSegment < modes.count else { return }
        onLightModeChanged?(modes[sender.selectedSegment])
    }

    @objc private func showGuide(_ sender: Any?) {
        onShowGuide?()
    }

    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard let rawControl = sender.identifier?.rawValue,
              let control = InputControl(rawValue: rawControl),
              let rawAction = sender.selectedItem?.representedObject as? String else { return }
        let profile = configuration.activeProfile
        if rawAction == recordShortcutToken {
            guard let result = KeyboardShortcutRecorder.record() else {
                reloadControls()
                return
            }
            switch result {
            case let .success(shortcut):
                onMappingChanged?(profile, control, .shortcut(shortcut))
            case let .failure(error):
                NSAlert(error: error).runModal()
                reloadControls()
            }
            return
        }
        guard let action = KeyAction(rawValue: rawAction) else {
            reloadControls()
            return
        }
        onMappingChanged?(profile, control, .preset(action))
    }

    @objc private func ledPreviewChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String else { return }
        if raw == "live" {
            onPreviewLedState?(nil)
        } else if let state = DialAgentState(rawValue: raw) {
            onPreviewLedState?(state)
        }
    }

    @objc private func grantAccessibility(_ sender: Any?) { onGrantAccessibility?() }
    @objc private func grantInputMonitoring(_ sender: Any?) { onGrantInputMonitoring?() }
    @objc private func quitStudio(_ sender: Any?) { onQuitVendor?() }
    @objc private func quit(_ sender: Any?) { onQuit?() }
    @objc private func showAgentHooks(_ sender: Any?) { onShowAgentHooks?() }
}