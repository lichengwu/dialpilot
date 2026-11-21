import AppKit
import DialPilotCore

/// Popover panel: device status, profile switching, key mappings,
/// Agent-light controls, and app actions — grouped into visual sections.
///
/// UX decisions (redesign):
/// - Status is a colored dot + one line, not a wall of text; battery and
///   power details live in a compact secondary line.
/// - Buttons say what they DO in plain simplified Chinese: 「写入设备」
///   (was 「离线备用」), 「原生模式/手势模式」 toggle (was 只用原生/启用手势),
///   「退出」 (was 结束). Destructive-ish actions are visually separated.
/// - Agent lights get a live state chip + preview picker so the user can
///   see each pattern on the device without a terminal.
final class SettingsViewController: NSViewController {
    var onProfileSelected: ((ProfileID) -> Void)?
    var onMappingChanged: ((ProfileID, InputControl, ControlBinding) -> Void)?
    var onRestartApplication: (() -> Void)?
    var onSyncHardware: (() -> Void)?
    var onToggleEnhancedMode: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onQuit: (() -> Void)?
    var onShowAgentHooks: (() -> Void)?
    /// Preview an agent-light state on the device (nil = back to live).
    var onPreviewLedState: ((DialAgentState?) -> Void)?
    /// Current live LED state, refreshed by the app delegate.
    var currentLedState: DialAgentState = .idle {
        didSet { if isViewLoaded { reloadLedChip() } }
    }

    private var configuration: AppConfiguration
    private var listenerActive = false
    private var accessibilityGranted = false
    private var deviceConnected = false
    private var powerStatus = DialPowerSnapshot()
    private var powerSaving = false
    private var hardwareSyncInProgress = false
    private var launchAtLoginEnabled = false
    private var notice: String?

    private let profileSelector = NSSegmentedControl(
        labels: ["AI", "系统"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let statusDot = NSView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let powerLabel = NSTextField(labelWithString: "")
    private let ledChip = NSTextField(labelWithString: "")
    private let ledPreviewPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private lazy var syncButton = NSButton(
        title: "写入设备",
        target: self,
        action: #selector(syncHardware(_:))
    )
    private lazy var restartButton = NSButton(
        title: "重启 App",
        target: self,
        action: #selector(restartApplication(_:))
    )
    private lazy var enhancedModeButton = NSButton(
        title: "原生模式",
        target: self,
        action: #selector(toggleEnhancedMode(_:))
    )
    private lazy var launchAtLoginButton = NSButton(
        checkboxWithTitle: "开机自动启动",
        target: self,
        action: #selector(toggleLaunchAtLogin(_:))
    )
    private var actionPopups: [InputControl: NSPopUpButton] = [:]
    private let recordShortcutToken = "__record_native_shortcut__"

    /// States offered in the preview picker, in semantic order.
    private static let previewStates: [DialAgentState] = [
        .idle, .thinking, .working, .attention, .notification, .error, .sweeping,
    ]

    init(configuration: AppConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 560))

        // ── Header: title + live status dot ─────────────────────────
        let title = NSTextField(labelWithString: "DialPilot")
        title.font = PanelTheme.titleFont

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusDot.widthAnchor.constraint(equalToConstant: 8),
            statusDot.heightAnchor.constraint(equalToConstant: 8),
        ])
        statusLabel.font = PanelTheme.captionFont
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        let statusRow = NSStackView(views: [statusDot, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 6

        let header = NSStackView(views: [title, NSView(), statusRow])
        header.orientation = .horizontal
        header.alignment = .centerY

        powerLabel.font = PanelTheme.captionFont
        powerLabel.textColor = .secondaryLabelColor

        // ── Profile section ─────────────────────────────────────────
        profileSelector.target = self
        profileSelector.action = #selector(profileChanged(_:))
        profileSelector.setAccessibilityLabel("当前按键组")
        profileSelector.controlSize = .regular

        let profileHint = PanelTheme.caption(
            "旋钮单按、双按可分别设置；按住 0.65 秒固定切换 AI／系统。"
        )
        let profileRow = NSStackView(views: [
            PanelTheme.sectionLabel("按键组"), profileSelector,
        ])
        profileRow.orientation = .horizontal
        profileRow.alignment = .centerY
        profileRow.spacing = 10

        let mappingGrid = makeMappingGrid()

        // ── Agent lights section ────────────────────────────────────
        ledChip.font = PanelTheme.monoFont
        ledChip.textColor = .secondaryLabelColor
        reloadLedChip()

        ledPreviewPopup.addItem(withTitle: "实时（跟随 Agent）")
        ledPreviewPopup.lastItem?.representedObject = "live"
        for state in Self.previewStates {
            ledPreviewPopup.addItem(withTitle: "预览：\(Self.stateDisplayName(state))")
            ledPreviewPopup.lastItem?.representedObject = state.rawValue
        }
        ledPreviewPopup.target = self
        ledPreviewPopup.action = #selector(ledPreviewChanged(_:))
        ledPreviewPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true

        let hooksButton = NSButton(
            title: "接入 Agent…",
            target: self,
            action: #selector(showAgentHooks(_:))
        )
        hooksButton.bezelStyle = .rounded
        hooksButton.controlSize = .small

        let ledRow = NSStackView(views: [
            PanelTheme.sectionLabel("状态灯"), ledChip, NSView(), ledPreviewPopup, hooksButton,
        ])
        ledRow.orientation = .horizontal
        ledRow.alignment = .centerY
        ledRow.spacing = 8

        let ledHint = PanelTheme.caption(
            "预览会在设备上保持该灯效；选「实时」恢复跟随 Agent 事件。"
        )

        // ── Device write section ────────────────────────────────────
        syncButton.bezelStyle = .rounded
        syncButton.toolTip = "把当前组的六个单按写入 AU05 离线存储；App 退出后设备用这一组"
        enhancedModeButton.bezelStyle = .rounded
        enhancedModeButton.toolTip = "原生模式：设备直接用机内六键；手势模式：App 接管，支持双按/长按"
        restartButton.bezelStyle = .rounded

        let deviceRow = NSStackView(views: [
            syncButton, enhancedModeButton, NSView(), restartButton,
        ])
        deviceRow.orientation = .horizontal
        deviceRow.alignment = .centerY
        deviceRow.spacing = 8

        let syncHint = PanelTheme.caption(
            "「写入设备」才会更新 AU05 机内六键；平时切组只改 App 内设置，不写设备。"
        )

        // ── Footer ──────────────────────────────────────────────────
        let quitButton = NSButton(
            title: "退出",
            target: self,
            action: #selector(quit(_:))
        )
        quitButton.bezelStyle = .rounded
        quitButton.contentTintColor = .secondaryLabelColor

        let footer = NSStackView(views: [launchAtLoginButton, NSView(), quitButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        // ── Assemble ────────────────────────────────────────────────
        let stack = NSStackView(views: [
            header,
            powerLabel,
            PanelTheme.separator(),
            profileRow,
            profileHint,
            mappingGrid,
            PanelTheme.separator(),
            ledRow,
            ledHint,
            PanelTheme.separator(),
            deviceRow,
            syncHint,
            PanelTheme.separator(),
            footer,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            profileRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            mappingGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            ledRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            deviceRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),
        ])
        for case let box as NSBox in stack.arrangedSubviews {
            box.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        reloadControls()
    }

    func update(
        configuration: AppConfiguration,
        listenerActive: Bool,
        accessibilityGranted: Bool,
        deviceConnected: Bool,
        powerStatus: DialPowerSnapshot,
        powerSaving: Bool,
        hardwareSyncInProgress: Bool,
        launchAtLoginEnabled: Bool,
        notice: String?
    ) {
        self.configuration = configuration
        self.listenerActive = listenerActive
        self.accessibilityGranted = accessibilityGranted
        self.deviceConnected = deviceConnected
        self.powerStatus = powerStatus
        self.powerSaving = powerSaving
        self.hardwareSyncInProgress = hardwareSyncInProgress
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.notice = notice

        if isViewLoaded {
            reloadControls()
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
                if categoryIndex > 0 {
                    popup.menu?.addItem(.separator())
                }
                let heading = NSMenuItem(title: category.rawValue, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                popup.menu?.addItem(heading)

                for action in KeyAction.allCases where action.category == category {
                    if action == .switchProfile, control != .knobDoublePress {
                        continue
                    }
                    let supported = action == .switchProfile || action.isAppOnly
                        || PresetNativeShortcutResolver.resolve(action) != .unsupported
                    let title = supported
                        ? action.displayName
                        : "\(action.displayName)（设备离线不支持）"
                    popup.addItem(withTitle: title)
                    popup.lastItem?.representedObject = action.rawValue
                    popup.lastItem?.isEnabled = supported
                }
            }

            popup.menu?.addItem(.separator())
            let recordItem = NSMenuItem(
                title: "录制键盘按键…",
                action: nil,
                keyEquivalent: ""
            )
            recordItem.representedObject = recordShortcutToken
            popup.menu?.addItem(recordItem)

            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
            actionPopups[control] = popup
            return [label, popup]
        }

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 4
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .leading
        grid.column(at: 1).xPlacement = .fill
        return grid
    }

    // MARK: - Reload

    private func reloadControls() {
        profileSelector.selectedSegment = configuration.activeProfile == .a ? 0 : 1
        profileSelector.isEnabled = !hardwareSyncInProgress
        syncButton.isEnabled = !hardwareSyncInProgress && deviceConnected
        restartButton.isEnabled = !hardwareSyncInProgress
        enhancedModeButton.isEnabled = !hardwareSyncInProgress
        enhancedModeButton.title = listenerActive ? "切到原生模式" : "启用手势模式"
        syncButton.title = hardwareSyncInProgress ? "写入中…" : "写入设备"
        launchAtLoginButton.state = launchAtLoginEnabled ? .on : .off
        launchAtLoginButton.isEnabled = !hardwareSyncInProgress
        ledPreviewPopup.isEnabled = deviceConnected && listenerActive
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
                }?.title = "录制键盘按键…"
            case let .shortcut(shortcut):
                matchingItem = popup?.itemArray.first {
                    ($0.representedObject as? String) == recordShortcutToken
                }
                matchingItem?.title = "自定义：\(shortcut.displayName)"
            }
            popup?.select(matchingItem)
            popup?.isEnabled = !hardwareSyncInProgress
        }

        reloadStatus()
        reloadLedChip()
        powerLabel.stringValue = powerSummary
    }

    private func reloadStatus() {
        let color: NSColor
        let message: String
        if !accessibilityGranted {
            color = PanelTheme.warn
            message = notice ?? "需要辅助使用权限才能启用手势；原生六键仍可用"
        } else if !listenerActive {
            color = PanelTheme.warn
            message = notice ?? "需要输入监控权限；原生按键仍可用"
        } else if powerSaving {
            color = .secondaryLabelColor
            message = notice ?? "设备省电中，唤醒后自动恢复手势"
        } else if let notice {
            if notice.hasPrefix("已写入") {
                color = PanelTheme.ok
            } else if notice.hasPrefix("正在写入") {
                color = .secondaryLabelColor
            } else {
                color = PanelTheme.warn
            }
            message = notice
        } else if deviceConnected {
            color = PanelTheme.ok
            let offlineName = configuration.offlineProfile?.displayName ?? "未设置"
            message = "已连接 · 手势可用 · 离线组：\(offlineName)"
        } else {
            color = .secondaryLabelColor
            message = "等待 AU05 连接…"
        }
        statusDot.layer?.backgroundColor = color.cgColor
        statusLabel.stringValue = message
        statusLabel.textColor = .labelColor
    }

    private func reloadLedChip() {
        ledChip.stringValue = "● \(Self.stateDisplayName(currentLedState))"
        ledChip.textColor = Self.stateColor(currentLedState)
    }

    private var powerSummary: String {
        let batteryText: String
        if let battery = powerStatus.battery {
            if battery.isCharging {
                batteryText = "充电中 \(battery.percent)%"
            } else if battery.isFullyCharged {
                batteryText = "已充满 \(battery.percent)%"
            } else {
                batteryText = "电量 \(battery.percent)%"
            }
        } else {
            batteryText = "电量 —"
        }
        let standbyText = powerStatus.standbyTimeSeconds.map(Self.durationText) ?? "—"
        let sleepText = powerStatus.sleepTimeSeconds.map(Self.durationText) ?? "—"
        let stateText = powerSaving || powerStatus.isStandby == true ? " · 省电中" : ""
        return "\(batteryText) · 待机 \(standbyText) · 关机 \(sleepText)\(stateText)"
    }

    private static func durationText(_ seconds: UInt32) -> String {
        if seconds > 0, seconds.isMultiple(of: 3_600) {
            return "\(seconds / 3_600) 小时"
        }
        if seconds > 0, seconds.isMultiple(of: 60) {
            return "\(seconds / 60) 分"
        }
        return "\(seconds) 秒"
    }

    static func stateDisplayName(_ state: DialAgentState) -> String {
        switch state {
        case .idle: return "空闲"
        case .thinking: return "思考（旋钮慢闪）"
        case .working: return "干活（旋钮常亮）"
        case .attention: return "完成（中键 10 秒）"
        case .notification: return "需审批（中下快闪）"
        case .error: return "出错（全亮闪 3 次）"
        case .sweeping: return "压缩（三灯流水）"
        case .sleeping: return "休眠"
        case .off: return "关闭"
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

    // MARK: - Actions

    @objc private func profileChanged(_ sender: NSSegmentedControl) {
        let profile: ProfileID = sender.selectedSegment == 0 ? .a : .b
        onProfileSelected?(profile)
    }

    @objc private func mappingChanged(_ sender: NSPopUpButton) {
        guard let rawControl = sender.identifier?.rawValue,
              let control = InputControl(rawValue: rawControl),
              let rawAction = sender.selectedItem?.representedObject as? String else {
            return
        }
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
                let alert = NSAlert(error: error)
                alert.runModal()
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

    @objc private func restartApplication(_ sender: Any?) {
        onRestartApplication?()
    }

    @objc private func syncHardware(_ sender: Any?) {
        onSyncHardware?()
    }

    @objc private func toggleEnhancedMode(_ sender: Any?) {
        onToggleEnhancedMode?()
    }

    @objc private func toggleLaunchAtLogin(_ sender: Any?) {
        onToggleLaunchAtLogin?()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit?()
    }

    @objc private func showAgentHooks(_ sender: Any?) {
        onShowAgentHooks?()
    }
}