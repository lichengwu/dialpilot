import Foundation

/// UI language resolution: follow the system by default.
/// Pure and injectable so tests can pin either language without touching
/// the real locale. Chinese is chosen when the top preferred language is
/// any zh variant (zh-Hans, zh-Hant, zh-CN, …); everything else gets English.
public enum DialLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case chinese = "zh"

    /// Resolves from an explicit preference list (e.g. Locale.preferredLanguages).
    public static func resolve(preferredLanguages: [String]) -> DialLanguage {
        guard let top = preferredLanguages.first?.lowercased() else { return .english }
        return top.hasPrefix("zh") ? .chinese : .english
    }

    /// Live resolution from the current user's system settings.
    public static var system: DialLanguage {
        resolve(preferredLanguages: Locale.preferredLanguages)
    }
}

/// Minimal bilingual string table for the app UI.
/// Keys are stable identifiers; values are (english, chinese).
/// Deliberately not NSLocalizedString/.strings: the app ships as a bare
/// SwiftPM executable bundle, and a typed table is unit-testable.
public enum L10n {
    /// Active language. The app sets this once at launch from the system;
    /// tests may pin it. Defaults to the system language.
    public static var language: DialLanguage = .system

    public static func text(_ key: Key) -> String {
        let pair = key.pair
        return language == .chinese ? pair.zh : pair.en
    }

    public struct Pair: Sendable {
        public let en: String
        public let zh: String
        public init(_ en: String, _ zh: String) {
            self.en = en
            self.zh = zh
        }
    }

    public enum Key: Sendable {
        // Panel sections
        case profileSection, lightSection, deviceSection
        case profileAI, profileSystem
        // Status
        case connectedGestures, waitingDevice, powerSaving, deviceNotResponding
        case needAccessibility, needInputMonitoring
        case offlineProfileNotSet
        // Permission banner
        case permissionTitle, permissionBody
        case grantAccessibility, grantInputMonitoring, openSettings
        // Buttons
        case quit, connectAgent
        // Light modes
        case lightModeAllOn, lightModeOff, lightModeSmart
        case lightModeAllOnHint, lightModeOffHint, lightModeSmartHint
        case lightGuideTitle, lightGuideSubtitle
        case guideWindowSubtitle, guideWindowHint
        case noticeMappingSavedAuto
        case noticeWritingDevice
        case previewLive, previewPrefix
        case customShortcut, recordShortcut
        case offlineUnsupported
        // Power
        case battery, charging, fullyCharged, standby, powerOff, saving
        // Usage stats card
        case usageTitle, usageToday, usageTotal, usageTop, usageNone
        case usageTimesSuffix
        // Multi-session visibility
        case sessionsActiveSuffix, sessionsWinning, sessionsAgoSeconds, sessionsAgoMinutes
        case sessionsNone, sessionsManual
        case usageLast7Days
        // Status bar accessibility/tooltip states
        case statusDisconnected, statusNeedsPermission, statusLowBattery
        case statusCharging, statusNormal
        // Agent states (short names for chips/cards)
        case stateIdle, stateThinking, stateWorking, stateAttention
        case stateNotification, stateError, stateSweeping
        // Agent state guide: when + how
        case guideIdleWhen, guideIdleHow
        case guideThinkingWhen, guideThinkingHow
        case guideWorkingWhen, guideWorkingHow
        case guideAttentionWhen, guideAttentionHow
        case guideNotificationWhen, guideNotificationHow
        case guideErrorWhen, guideErrorHow
        case guideSweepingWhen, guideSweepingHow
        // Hooks window
        case hooksWindowTitle, hooksIntro
        case hooksColAgent, hooksColStatus, hooksColAction
        case hooksRefresh, hooksClose
        case hooksDetected, hooksNotDetected, hooksConnected
        case hooksInstall, hooksUninstall
        case hooksInstallFirst
        // Misc
        case lightPreviewHint
        // Hooks window dynamic messages
        case hooksNotDetectedTitle, openDownloadPage, cancel
        case hooksUnsupportedLocal, hooksReadbackFailed
        case hooksCodexConnected, hooksConnectedRestart
        case hooksInstallFailed, hooksUninstallFailed
        case hooksNoConfig, hooksNoMarker, hooksRemoved
        case hooksDshRemoved, hooksDshReadbackFailed, hooksDshConnected, hooksDshWriteFailed
        case qwenListenerFailedTitle, qwenListenerFailedBody
        case qwenGuideTitle, qwenGuideBody, qwenCopyConfig
        case qwenCopied, qwenListenerStarted
        case hooksInstalledNotConnected, hooksInstallTooltip, hooksInstallFirstTooltip
        // Runtime notices (AppDelegate)
        case noticeWritingQuit, noticeConfigReadFailed
        case noticeAppOnlySaved, noticePowerSaving, noticeDeviceRestarting
        case noticeConfigUnusable, noticeNeedAccessibility, noticeStudioRunning
        case noticeGestureInvalid, noticeListenFailed, noticeWaitingDeviceReturn
        case noticeDeviceRemoved, noticeActionFailed, noticeConfigUnusableNoWrite, noticeStudioQuitting
        case noticeStudioNotQuit, noticeWriteFailed, noticeStudioDuringWrite, noticeWroteMarkerSaveFailed
        case noticeWroteAppOnly, noticeWrote, noticeSyncAborted
        case noticeSyncFailedPartial, noticeSyncAbortedShort, noticeSyncFailed
        case noticeConfigLocationUnavailable, noticeConfigSaveFailed
        case alertStudioNotQuitTitle, alertStudioNotQuitBody, alertOK
        case alertSyncIncompleteTitle, alertSyncFailedFallback
        case syncConfigLocationUnavailable
        case noticeMacSleeping, noticeMacShuttingDown, noticeStudioOpened
        case actionSendFailed, actionShortcutDataFailed, actionKeyboardEventFailed
        case ctlAppNotReady, ctlRendererNotReady, ctlUnknownState, ctlMissingEvent, ctlUnknownCommand
        case errInputDenied, errInputPrompt
        case errManagerOpen, errDeviceNotFound, errDeviceOpen, errOfflineWrite
        case errReportWrite, errUnsupportedAction
        case errParseRequest
        case batterySuffix
        case errListenerOpen, errHeartbeat, errListenerOffline, errOnlineLost
        case errPowerTransition, errLedBusy, errLedTimeout, errLedWrite
        case recorderTitle, recorderBody, recorderCancel, recorderSave
        case doNothing
        case recorderWaiting, recorderPress
        case errAgentNotDetected, errInvalidJSON, errUnsupportedTarget

        var pair: Pair {
            switch self {
            case .profileSection: return Pair("Key Profile", "按键组")
            case .lightSection: return Pair("Lights", "灯效")
            case .deviceSection: return Pair("Device", "设备")
            case .profileAI: return Pair("AI", "AI")
            case .profileSystem: return Pair("System", "系统")
            case .connectedGestures: return Pair("Connected · gestures active", "已连接 · 手势可用")
            case .deviceNotResponding: return Pair(
                "Connected · not responding",
                "已连接 · 未响应")
            case .waitingDevice: return Pair("Waiting for AU05…", "等待 AU05 连接…")
            case .powerSaving: return Pair(
                "Device saving power; gestures resume on wake.",
                "设备省电中，唤醒后自动恢复手势")
            case .needAccessibility: return Pair(
                "Accessibility permission needed for gestures; native keys still work.",
                "需要辅助使用权限才能启用手势；原生六键仍可用")
            case .needInputMonitoring: return Pair(
                "Input Monitoring permission needed; native keys still work.",
                "需要输入监控权限；原生按键仍可用")
            case .offlineProfileNotSet: return Pair("not set", "未设置")
            case .permissionTitle: return Pair("Permissions required", "需要系统权限")
            case .permissionBody: return Pair(
                "DialPilot needs these permissions for gestures and agent lights. Native keys work without them.",
                "手势与 Agent 灯效需要以下权限；不授权时原生六键仍可用。")
            case .grantAccessibility: return Pair("Grant Accessibility", "授权辅助使用")
            case .grantInputMonitoring: return Pair("Grant Input Monitoring", "授权输入监控")
            case .openSettings: return Pair("Open Settings", "打开系统设置")
            case .quit: return Pair("Quit", "退出")
            case .connectAgent: return Pair("Connect Agent…", "接入 Agent…")
            case .lightModeAllOn: return Pair("All On", "全开")
            case .lightModeOff: return Pair("Off", "关闭")
            case .lightModeSmart: return Pair("Smart", "智能")
            case .lightModeAllOnHint: return Pair(
                "All four LEDs stay lit (same as the native all-on mode).",
                "四颗灯全部常亮（与原生全亮模式一致）。")
            case .lightModeOffHint: return Pair(
                "All LEDs off (same as the native off mode).",
                "全部灯熄灭（与原生关闭模式一致）。")
            case .lightModeSmartHint: return Pair(
                "LEDs follow agent events: knob = heartbeat, middle = done, middle+bottom = approve.",
                "灯随 Agent 事件变化：旋钮=心跳，中键=完成，中+下快闪=需审批。")
            case .lightGuideTitle: return Pair("Smart light guide", "智能灯效说明")
            case .lightGuideSubtitle: return Pair(
                "Swipe to see when each pattern lights up and what it looks like.",
                "左右滑动查看每种灯效何时亮、怎么亮。")
            case .guideWindowSubtitle: return Pair(
                "Seven states, one dial. Here is when each light comes on and what it looks like.",
                "七种状态，一颗旋钮。每种灯何时亮、长什么样，都在这里。")
            case .guideWindowHint: return Pair(
                "← → or swipe to browse · click or Esc to close",
                "← → 或左右滑动浏览 · 点击任意处或 Esc 关闭")
            case .noticeMappingSavedAuto: return Pair(
                "Saved. Updating the device automatically…",
                "已保存，正在自动更新设备…")
            case .previewLive: return Pair("Live (follow agents)", "实时（跟随 Agent）")
            case .previewPrefix: return Pair("Preview: ", "预览：")
            case .customShortcut: return Pair("Custom: ", "自定义：")
            case .recordShortcut: return Pair("Record keyboard shortcut…", "录制键盘按键…")
            case .offlineUnsupported: return Pair(" (not supported offline)", "（设备离线不支持）")
            case .usageTitle: return Pair("Usage", "使用统计")
            case .usageToday: return Pair("Today", "今日")
            case .usageTotal: return Pair("All time", "累计")
            case .usageTop: return Pair("Most used", "最常用")
            case .usageNone: return Pair("No use yet", "还没用过")
            case .usageTimesSuffix: return Pair(" times", " 次")
            case .sessionsActiveSuffix: return Pair(" sessions", " 个会话")
            case .sessionsWinning: return Pair("on LEDs", "正在亮灯")
            case .sessionsAgoSeconds: return Pair("s ago", " 秒前")
            case .sessionsAgoMinutes: return Pair("m ago", " 分钟前")
            case .sessionsNone: return Pair("No active agent sessions", "当前没有活跃的 Agent 会话")
            case .sessionsManual: return Pair("manual", "手动")
            case .usageLast7Days: return Pair("Last 7 days", "最近 7 天")
            case .statusDisconnected: return Pair("Device not connected", "设备未连接")
            case .statusNeedsPermission: return Pair("Permission needed", "需要授权")
            case .statusLowBattery: return Pair("Battery low", "电量低")
            case .statusCharging: return Pair("Charging", "充电中")
            case .statusNormal: return Pair("Ready", "就绪")
            case .battery: return Pair("Battery", "电量")
            case .charging: return Pair("Charging", "充电中")
            case .fullyCharged: return Pair("Full", "已充满")
            case .standby: return Pair("Standby", "待机")
            case .powerOff: return Pair("Power off", "关机")
            case .saving: return Pair("saving", "省电中")
            case .stateIdle: return Pair("Idle", "空闲")
            case .stateThinking: return Pair("Thinking", "思考")
            case .stateWorking: return Pair("Working", "干活")
            case .stateAttention: return Pair("Done", "完成")
            case .stateNotification: return Pair("Approve", "需审批")
            case .stateError: return Pair("Error", "出错")
            case .stateSweeping: return Pair("Compacting", "压缩")
            case .guideIdleWhen: return Pair("No agent activity", "没有 Agent 活动")
            case .guideIdleHow: return Pair("All LEDs off", "全部灯熄灭")
            case .guideThinkingWhen: return Pair("Agent received your prompt", "Agent 收到你的提问")
            case .guideThinkingHow: return Pair("Knob slow blink (1.2 s)", "旋钮慢闪（1.2 秒）")
            case .guideWorkingWhen: return Pair("Agent is running tools", "Agent 正在执行工具")
            case .guideWorkingHow: return Pair("Knob solid", "旋钮常亮")
            case .guideAttentionWhen: return Pair("Agent finished a turn", "Agent 完成一轮回答")
            case .guideAttentionHow: return Pair("Middle key lit 10 s, then off", "中键亮 10 秒后自动灭")
            case .guideNotificationWhen: return Pair("Agent needs your approval", "Agent 需要你审批")
            case .guideNotificationHow: return Pair("Middle + bottom fast blink (0.6 s)", "中+下快闪（0.6 秒）")
            case .guideErrorWhen: return Pair("A tool or session failed", "工具或会话出错")
            case .guideErrorHow: return Pair("All LEDs flash 3×, then restore", "全灯闪 3 次后恢复之前状态")
            case .guideSweepingWhen: return Pair("Agent is compacting context", "Agent 正在压缩上下文")
            case .guideSweepingHow: return Pair("Three-LED chase (0.5 s/step)", "三灯流水（0.5 秒一步）")
            case .hooksWindowTitle: return Pair("Agent Light Connections", "Agent 灯效接入")
            case .hooksIntro: return Pair(
                "Pick agents to connect. Install detects the software first, backs up its config, and only adds hooks tagged dialpilot; uninstall removes only those entries. Your existing config is preserved.",
                "选择要接入灯效的 Agent。安装前会检测软件是否已安装；安装只新增带 dialpilot 标记的 hooks，卸载只移除这些条目，你已有的配置原样保留。")
            case .hooksColAgent: return Pair("Agent", "Agent")
            case .hooksColStatus: return Pair("Status", "检测 / 接入")
            case .hooksColAction: return Pair("Action", "操作")
            case .hooksRefresh: return Pair("Re-detect", "重新检测")
            case .hooksClose: return Pair("Close", "关闭")
            case .hooksDetected: return Pair("Installed", "已安装")
            case .hooksNotDetected: return Pair("Not detected", "未检测到该软件")
            case .hooksConnected: return Pair("Connected ✓", "已接入 ✓")
            case .hooksInstall: return Pair("Connect", "接入")
            case .hooksUninstall: return Pair("Remove", "卸载")
            case .hooksInstallFirst: return Pair(
                "Install this software first, then come back to connect lights.",
                "请先安装该软件，再回来接入灯效。")
            case .lightPreviewHint: return Pair(
                "Preview holds a pattern on the device; Live returns to agent events.",
                "预览会在设备上保持该灯效；选「实时」恢复跟随 Agent 事件。")
            case .hooksNotDetectedTitle: return Pair("Not detected: ", "未检测到 ")
            case .openDownloadPage: return Pair("Open Download Page", "打开下载页")
            case .cancel: return Pair("Cancel", "取消")
            case .hooksUnsupportedLocal: return Pair(
                " does not support local config install yet.",
                " 暂不支持本地配置安装。")
            case .hooksReadbackFailed: return Pair(
                "Read-back verification failed: marked entries missing.",
                "读回校验失败：标记条目缺失。")
            case .hooksCodexConnected: return Pair(
                "Codex connected. Run /hooks inside Codex to approve the entries before they fire.",
                "已接入 Codex。请在 Codex 内运行 /hooks 批准各条目后生效。")
            case .hooksConnectedRestart: return Pair(
                " connected. Restart that agent's session to take effect.",
                " 已接入。重启该 Agent 的会话后生效。")
            case .hooksInstallFailed: return Pair("Install failed: ", "安装失败：")
            case .hooksUninstallFailed: return Pair("Uninstall failed: ", "卸载失败：")
            case .hooksNoConfig: return Pair("No config file; nothing to remove.", "没有配置文件，无需卸载。")
            case .hooksNoMarker: return Pair("No dialpilot entries found; nothing to remove.", "未找到 dialpilot 条目，无需卸载。")
            case .hooksRemoved: return Pair(
                " light hooks removed (other config preserved).",
                " 的灯效 hooks 已卸载（其余配置保留）。")
            case .hooksDshRemoved: return Pair("DSH light hooks removed.", "已卸载 DSH 灯效 hooks。")
            case .hooksDshReadbackFailed: return Pair(
                "Read-back verification failed: DSH marked entry missing.",
                "读回校验失败：DSH 标记条目缺失。")
            case .hooksDshConnected: return Pair(
                "DeepSeek Harness connected. Restart dsh to take effect.",
                "已接入 DeepSeek Harness。重启 dsh 后生效。")
            case .hooksDshWriteFailed: return Pair("DSH write failed: ", "DSH 写入失败：")
            case .qwenListenerFailedTitle: return Pair("QwenWork listener failed to start", "千问办公监听启动失败")
            case .qwenListenerFailedBody: return Pair(
                "Could not start the loopback listener on 127.0.0.1:27950 (port may be in use). Close the occupying program and retry.",
                "无法在 127.0.0.1:27950 启动本机监听（端口可能被占用）。请关闭占用程序后重试。")
            case .qwenGuideTitle: return Pair("QwenWork connection (enterprise premium)", "千问办公接入（企业旗舰版）")
            case .qwenGuideBody: return Pair(
                """
                The loopback listener is running (127.0.0.1:27950/qwenwork, loopback only).

                QwenWork hooks can only be configured in the enterprise console (Organization & Security → Security Controls → Hooks Rules), HTTP type only. Click Copy Config, then paste for each event: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, Notification, PreCompact.

                Hooks are enterprise-premium only; the personal edition cannot connect lights.

                On uninstall the listener stops — also clear the rules in the console.
                """,
                """
                本机监听已启动（127.0.0.1:27950/qwenwork，仅回环）。

                千问办公的 hooks 只能在企业管理后台配置（组织与安全 → 安全管控 → Hooks 规则），且仅支持 HTTP 类型。点「复制配置」后，到后台为下列事件分别粘贴：SessionStart、UserPromptSubmit、PreToolUse、PostToolUse、Stop、Notification、PreCompact。

                hooks 仅企业旗舰版支持；个人版无法接入灯效。

                卸载时监听会停止，并请同步到后台清空对应规则。
                """)
            case .qwenCopyConfig: return Pair("Copy Config", "复制配置")
            case .qwenCopied: return Pair(
                "Listener running; config copied. Paste it in the enterprise console.",
                "监听已启动，配置已复制；请到企业管理后台粘贴。")
            case .qwenListenerStarted: return Pair(
                "Listener running. Click Copy Config any time to get the console config again.",
                "监听已启动；可随时点「复制配置」重新获取后台配置。")
            case .hooksInstalledNotConnected: return Pair("Installed · not connected", "已安装 · 未接入")
            case .hooksInstallTooltip: return Pair(
                "Backs up the config, then only adds hooks tagged dialpilot",
                "备份原配置后只新增 dialpilot 标记的 hooks")
            case .hooksInstallFirstTooltip: return Pair(
                "Install this software first to connect",
                "先安装该软件才能接入")
            case .noticeWritingQuit: return Pair(
                "Writing to AU05; quit the app after it finishes.",
                "AU05 写入中；完成后再退出 App。")
            case .noticeConfigReadFailed: return Pair("Config read failed: ", "配置文件读取失败：")
            case .noticeAppOnlySaved: return Pair(
                "App-only key saved; runs only while the app is open. Its offline slot is written empty.",
                "App 专属键已保存；只在 App 开启时执行，离线六键会为它写入空槽。")
            case .noticePowerSaving: return Pair(
                "Device idle / saving power; gestures resume when the controller wakes.",
                "闲置省电中；控制器醒来后会自动恢复三种手势。")
            case .noticeDeviceRestarting: return Pair(
                "AU05 restarted; reconnecting automatically.",
                "AU05 重新启动；正在自动重建连接。")
            case .noticeConfigUnusable: return Pair(
                "Config unusable; AU05 stays in native device mode.",
                "配置文件无法使用；AU05 保持设备原生模式。")
            case .noticeNeedAccessibility: return Pair(
                "Native six keys still work; allow Accessibility to enable double-press and long-press.",
                "原生六键仍可用；允许「辅助使用」后，双按与长按才会启用。")
            case .noticeStudioRunning: return Pair(
                "Ulanzi Studio is running and owns the keys. Write to Device will quit it and write.",
                "Ulanzi Studio 正在运行，按键由它接管。点「写入设备」会自动退出它并写入。")
            case .noticeGestureInvalid: return Pair(
                "Native six keys still work; advanced gesture config invalid: ",
                "原生六键仍可用；进阶手势设置无效：")
            case .noticeListenFailed: return Pair("Listen failed: ", "监听失败：")
            case .noticeWaitingDeviceReturn: return Pair(
                "Waiting for AU05 to power back on; will reconnect automatically.",
                "等待 AU05 重新开机；侦测到后会自动接回。")
            case .noticeDeviceRemoved: return Pair(
                "AU05 removed; pending knob press cancelled.",
                "AU05 已移除；未完成的旋钮按压已取消。")
            case .noticeActionFailed: return Pair("Key action failed: ", "按键执行失败：")
            case .noticeConfigUnusableNoWrite: return Pair(
                "Config unusable; nothing written to AU05.",
                "配置文件无法使用；未写入 AU05。")
            case .noticeStudioQuitting: return Pair(
                "Ulanzi Studio is running; quitting it automatically…",
                "Ulanzi Studio 正在运行；正在自动退出它…")
            case .noticeStudioNotQuit: return Pair(
                "Ulanzi Studio did not quit; nothing written to AU05.",
                "Ulanzi Studio 未退出；未写入 AU05。")
            case .noticeWriteFailed: return Pair("Not written to AU05: ", "未写入 AU05：")
            case .noticeWritingDevice: return Pair(
                "Updating the device…", "正在更新设备…")
            case .noticeStudioDuringWrite: return Pair(
                "Ulanzi Studio opened during the write; device contents uncertain. Quit it and the update will retry automatically.",
                "Ulanzi Studio 在写入时开启；设备内容不确定。请关闭它，更新会自动重试。")
            case .noticeWroteMarkerSaveFailed: return Pair(
                "Device updated, but saving the sync marker failed: ",
                "设备已更新，但同步状态保存失败：")
            case .noticeWroteAppOnly: return Pair(
                "Device updated. Keys work after the app quits; app-only keys (voice / Fn double-tap) need the app running.",
                "设备已更新。关掉 App 按键仍可用；App 专属键（语音／Fn 双击）需 App 运行。")
            case .noticeWrote: return Pair(
                "Device updated. Keys work even after the app quits.",
                "设备已更新。关掉 App 按键仍可用。")
            case .noticeSyncAborted: return Pair(
                "Sync aborted: ",
                "同步中止：")
            case .noticeSyncFailedPartial: return Pair(
                "Sync failed: ",
                "同步失败：")
            case .noticeSyncAbortedShort: return Pair(
                " Six-key write not started; keep the device connected and retry.",
                " 六键尚未开始写入；请保持连接再试。")
            case .noticeSyncFailed: return Pair(
                " Device may be partially written; keep it connected and press Write to Device again.",
                " 设备可能只写入部分；请保持连接，再按「写入设备」。")
            case .noticeConfigLocationUnavailable: return Pair(
                "Config location unavailable; this change was not saved.",
                "配置文件位置不可用，这次变更尚未保存。")
            case .noticeConfigSaveFailed: return Pair("Config save failed: ", "配置文件保存失败：")
            case .alertStudioNotQuitTitle: return Pair(
                "Ulanzi Studio did not quit; cannot write to AU05",
                "Ulanzi Studio 没有退出，无法写入 AU05")
            case .alertStudioNotQuitBody: return Pair(
                "Ulanzi Studio owns the AU05 and could not be quit automatically. Quit it fully (right-click its Dock icon → Quit, or ⌘Q), then press Write to Device again.",
                "Ulanzi Studio 正在接管 AU05，且未能自动退出。请手动完全退出它（程序坞右键图标选「退出」，或 ⌘Q），然后再点一次「写入设备」。")
            case .alertOK: return Pair("OK", "知道了")
            case .alertSyncIncompleteTitle: return Pair(
                "Write to Device did not complete",
                "「写入设备」没有完成")
            case .alertSyncFailedFallback: return Pair("Sync failed.", "同步失败。")
            case .syncConfigLocationUnavailable: return Pair(
                "Config location unavailable.",
                "配置文件位置不可用。")
            case .noticeMacSleeping: return Pair(
                "Mac is going to sleep; AU05 reverted to native device keys.",
                "Mac 即将睡眠；AU05 已退回设备原生按键。")
            case .noticeMacShuttingDown: return Pair(
                "Mac is shutting down; AU05 reverted to native device keys.",
                "Mac 即将关机；AU05 已退回设备原生按键。")
            case .noticeStudioOpened: return Pair(
                "Ulanzi Studio opened; AU05 reverted to native device keys.",
                "Ulanzi Studio 已开启；AU05 已退回设备原生按键。")
            case .actionSendFailed: return Pair("Could not send ", "无法送出「")
            case .actionShortcutDataFailed: return Pair(
                "Could not send shortcut data (page/value out of range).",
                "无法送出快捷键数据（page/value 超出范围）。")
            case .actionKeyboardEventFailed: return Pair(
                "macOS could not create the keyboard event.",
                "macOS 无法建立键盘事件。")
            case .ctlAppNotReady: return Pair("App not ready", "App 未就绪")
            case .ctlRendererNotReady: return Pair("LED renderer not ready", "灯效渲染器未就绪")
            case .ctlUnknownState: return Pair("Unknown state: ", "未知状态：")
            case .ctlMissingEvent: return Pair("Missing event", "缺少 event")
            case .ctlUnknownCommand: return Pair("Unknown command: ", "未知命令：")
            case .errInputDenied: return Pair(
                "Input Monitoring was denied. Allow DialPilot in System Settings → Privacy & Security → Input Monitoring.",
                "输入监控权限已被拒绝。请到「系统设置 → 隐私与安全性 → 输入监控」允许 DialPilot。")
            case .errInputPrompt: return Pair(
                "Input Monitoring requested. After allowing DialPilot, press Restart App.",
                "已要求输入监控权限。允许 DialPilot 后，请按「重启 App」。")
            case .errManagerOpen: return Pair("Could not open the HID manager (", "无法开启 HID 管理器（")
            case .errDeviceNotFound: return Pair(
                "Dial not found (VID 0xFFF1, PID 0x00DD, usagePage 0xFFFC, usage 1).",
                "找不到 Dial（VID 0xFFF1、PID 0x00DD、usagePage 0xFFFC、usage 1）。")
            case .errDeviceOpen: return Pair(
                "Dial found, but could not open the custom HID interface (",
                "找到 Dial，但无法开启 custom HID 接口（")
            case .errOfflineWrite: return Pair(
                "AU05 could not confirm return to native mode (",
                "AU05 无法确认回到原生模式（")
            case .errReportWrite: return Pair("Failed to write hardware action index ", "写入硬件动作 index ")
            case .errUnsupportedAction: return Pair(
                " cannot be executed offline by the AU05.",
                " 无法由 AU05 离线执行。")
            case .errParseRequest: return Pair("Could not parse request", "无法解析请求")
            case .batterySuffix: return Pair(", battery ", "，电量 ")
            case .errListenerOpen: return Pair("Could not open the AU05 HID listener (", "无法开启 AU05 HID 监听器（")
            case .errHeartbeat: return Pair(
                "AU05 online mode interrupted; reverted to native device keys (",
                "AU05 在线模式中断；已退回设备原生按键（")
            case .errListenerOffline: return Pair(
                "AU05 offline command failed; quit the app and let the device recover (",
                "AU05 离线指令失败；请退出 App，等待设备自动恢复（")
            case .errOnlineLost: return Pair(
                "Advanced gestures stopped; AU05 reverted to native device keys.",
                "进阶手势已停止；AU05 已退回设备原生按键。")
            case .errPowerTransition: return Pair(
                "AU05 power-saving state changed; restart DialPilot.",
                "AU05 省电模式状态已改变；请重新启动 DialPilot。")
            case .errLedBusy: return Pair(
                "An AU05 light operation is in progress; try again shortly.",
                "AU05 灯效操作正在进行中；请稍后再试。")
            case .errLedTimeout: return Pair(
                "AU05 light command timed out; the device may be asleep — press any key to wake, then retry.",
                "AU05 灯效命令超时；设备可能已休眠，按任意键唤醒后重试。")
            case .errLedWrite: return Pair("AU05 light write failed (", "AU05 灯效写入失败（")
            case .recorderTitle: return Pair("Record hardware shortcut", "录制硬件快捷键")
            case .recorderBody: return Pair(
                "Press a key or chord directly. Left/right Option, Control, Shift, Command are distinguished.",
                "请直接按下按键或组合键。可分辨左／右 Option、Control、Shift、Command。")
            case .recorderCancel: return Pair("Cancel", "取消")
            case .recorderSave: return Pair("Save", "保存")
            case .doNothing: return Pair("Do nothing", "不做事")
            case .recorderWaiting: return Pair("Waiting for keys…", "等待按键…")
            case .recorderPress: return Pair("Press the shortcut", "请按下快捷键")
            case .errAgentNotDetected: return Pair(
                " not detected. Install it first, then come back to connect lights.",
                " 未检测到。请先安装该软件，再回来接入灯效。")
            case .errInvalidJSON: return Pair(
                "The existing config is not valid JSON; the original file was kept untouched.",
                "现有配置文件不是合法 JSON；已保留原文件，未做任何修改。")
            case .errUnsupportedTarget: return Pair(
                " uses a special connection flow, not local config install.",
                " 使用特殊接入流程，不走本地配置安装。")
            }
        }
    }
}