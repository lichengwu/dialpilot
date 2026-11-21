import AppKit
import OSLog
import ServiceManagement
import DialPilotCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hardwareConfigurator: any HardwareConfigurator
    private var configuration = AppConfiguration.default
    private var configStore: ConfigStore?
    private var statusItem: NSStatusItem?
    private var panelController: DialPanelController?
    private var settingsViewController: SettingsViewController?
    private var hardwareListener: IOKitHardwareListener?
    private var ledRenderer: LedRenderer?
    private var ctlServer: CtlSocketServer?
    private var agentHooksWindowController: AgentHooksWindowController?
    private var guideWindowController: GuideWindowController?
    private var qwenWorkListener: QwenWorkHookListener?
    private var ledSessionAggregator = DialLedSessionAggregator()
    private var ledStaleTimer: Timer?
    private var autoSyncWorkItem: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let actionPerformer = ActionPerformer()
    private var knobPressStateMachine = KnobPressStateMachine()
    private var knobSinglePressTimer: Timer?
    private var powerHandoffTimer: Timer?
    private var connectionRecoveryTimer: Timer?
    private var connectionRecoveryAttemptsRemaining = 0
    private var powerHandoffStateMachine = DialPowerHandoffStateMachine(idleInterval: 300)
    private let logger = Logger(
        subsystem: "dev.lichengwu.dialpilot",
        category: "HID"
    )

    private var listenerActive = false
    private var accessibilityGranted = false
    private var deviceConnected = false
    /// False when the USB interface is enumerated but the knob never answers
    /// (switched off, cable only charging). See `DialDeviceLiveness`.
    private var deviceResponsive = true
    private var devicePowerStatus = DialPowerSnapshot()
    private var powerSaving = false
    private var hardwareSyncInProgress = false
    private var vendorInterferedDuringHardwareSync = false
    private var needsHardwareSync = false
    private var configurationReady = false
    private var offlineStateUnconfirmed = false
    private var notice: String?

    // Usage statistics: local counters, debounced persistence. Never
    // blocks input handling; a failed save just retries on next event.
    private var usageStats = DialUsageStats()
    private var usageStatsURL: URL?
    private var usageSaveWorkItem: DispatchWorkItem?
    private var appearanceObserver: NSObjectProtocol?

    override init() {
        hardwareConfigurator = IOKitHardwareConfigurator()
        super.init()
    }

    init(hardwareConfigurator: any HardwareConfigurator) {
        self.hardwareConfigurator = hardwareConfigurator
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadConfiguration()
        loadUsageStats()
        DebugLog.log("launch: offlineProfile=\(configuration.offlineProfile?.rawValue ?? "nil") needsHardwareSync=\(needsHardwareSync)")
        configureStatusItemAndPanel()
        configureHardwareListener()
        configureLedRendering()
        configureLifecycleObservers()
        enableLaunchAtLoginByDefault()
        observeMenuBarAppearance()
        refreshUI()

        // The six-key backup writes itself. No button, no confirmation —
        // the complexity stays on this side. If the device is not here yet,
        // the connect handler retries once it appears.
        if needsHardwareSync {
            scheduleAutoSync(delay: 1.0)
        }
        startHardwareListener(promptForPermission: true)
        scheduleConnectionRecovery()

        if ProcessInfo.processInfo.environment["DIALPILOT_SHOW_SETTINGS"] == "1" {
            DispatchQueue.main.async { [weak self] in
                self?.showPanel()
            }
        }
    }

    /// Launch at login is on by default — a menu-bar companion that is not
    /// running is a dead dial. Registered once; if the user later removes
    /// it from System Settings we do not fight them (only register when
    /// status is .notRegistered, never re-enable after .disabled).
    private func enableLaunchAtLoginByDefault() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        do {
            try service.register()
        } catch {
            logger.error("Launch-at-login default registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushUsageStats()
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
        let notificationCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        powerHandoffTimer?.invalidate()
        powerHandoffTimer = nil
        connectionRecoveryTimer?.invalidate()
        connectionRecoveryTimer = nil
        resetKnobPressState()
        actionPerformer.releaseAll()
        ctlServer?.stop()
        ctlServer = nil
        qwenWorkListener?.stop()
        qwenWorkListener = nil
        ledStaleTimer?.invalidate()
        ledStaleTimer = nil
        ledRenderer?.shutdown()
        ledRenderer = nil
        if let error = hardwareListener?.stop() {
            logger.error("Offline shutdown failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if hardwareSyncInProgress {
            notice = L10n.text(.noticeWritingQuit)
            refreshUI()
            return .terminateCancel
        }
        // Give the LED baseline restore a chance to land before the process
        // dies. shutdown() writes asynchronously (per-frame ACK, 2 s timeout
        // each); terminating immediately used to race it and could leave the
        // last agent pattern lit. Reply later once the write settles, with a
        // 3 s cap so a hung device can never block quitting.
        guard let renderer = ledRenderer else { return .terminateNow }
        ledRenderer = nil
        var replied = false
        let reply: (NSApplication.TerminateReply) -> Void = { reply in
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: reply == .terminateNow)
        }
        renderer.shutdown {
            DispatchQueue.main.async { reply(.terminateNow) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { reply(.terminateNow) }
        return .terminateLater
    }

    // MARK: - LED rendering + ctl socket

    private func showAgentHooksWindow() {
        if agentHooksWindowController == nil {
            let controller = AgentHooksWindowController()
            controller.onStartQwenWorkListener = { [weak self] in
                self?.startQwenWorkListener()
            }
            controller.onStopQwenWorkListener = { [weak self] in
                self?.qwenWorkListener?.stop()
                self?.qwenWorkListener = nil
            }
            controller.isQwenWorkListenerRunning = { [weak self] in
                self?.qwenWorkListener?.isRunning ?? false
            }
            controller.qwenWorkSnippets = { [weak self] in
                guard let token = self?.qwenWorkListener?.token else { return [:] }
                let port = self?.qwenWorkListener?.port ?? DialQwenWorkHookHandler.defaultPort
                return DialQwenWorkHookHandler.consoleSnippets(port: port, token: token)
            }
            agentHooksWindowController = controller
        }
        // The panel floats at status-bar level; leaving it up would cover
        // the window this button just opened.
        panelController?.dismiss(reason: "agent-hooks")
        agentHooksWindowController?.showWindow(nil)
        agentHooksWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Raycast-style full-screen light guide: swipe / arrow keys to move,
    /// click or Esc to dismiss. A separate window, not an inline strip —
    /// the panel never changes height, so the blank-gap bug is gone by
    /// construction.
    private func showGuideWindow() {
        if guideWindowController == nil {
            guideWindowController = GuideWindowController()
        }
        panelController?.dismiss(reason: "guide")
        guideWindowController?.present()
    }

    /// Starts the loopback listener on demand (install flow only; never at
    /// launch). Returns the bearer token on success, nil on failure.
    private func startQwenWorkListener() -> String? {
        if let existing = qwenWorkListener, existing.isRunning {
            return existing.token
        }
        let listener = QwenWorkHookListener { [weak self] state in
            guard let self, let renderer = self.ledRenderer else { return }
            let resolved = self.ledSessionAggregator.record(
                session: "qwenwork", state: state, now: Date().timeIntervalSince1970,
                agent: "qwenwork"
            )
            renderer.request(resolved)
            self.refreshUI()
        }
        do {
            try listener.start()
            qwenWorkListener = listener
            return listener.token
        } catch {
            logger.error("QwenWork listener start failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func configureLedRendering() {
        let renderer = LedRenderer(
            apply: { [weak self] desired, expected, force, completion in
                guard let listener = self?.hardwareListener, self?.listenerActive == true else {
                    completion(IOKitHardwareListenerError.onlinePrerequisiteLost)
                    return
                }
                listener.applyLedState(desired, expected: expected, force: force, completion: completion)
            },
            readState: { [weak self] completion in
                guard let listener = self?.hardwareListener, self?.listenerActive == true else {
                    completion(nil, IOKitHardwareListenerError.onlinePrerequisiteLost)
                    return
                }
                listener.readLedState(completion: completion)
            }
        )
        ledRenderer = renderer
        applyLightMode(configuration.lightMode)
        let staleTimer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let renderer = self.ledRenderer else { return }
            let before = self.ledSessionAggregator.activeSessionCount
            let resolved = self.ledSessionAggregator.prune(now: Date().timeIntervalSince1970)
            if resolved != renderer.state {
                renderer.request(resolved)
            }
            // Session count changed (a stale one dropped): refresh the
            // panel's "who is on the LEDs" row even if the state is same.
            if before != self.ledSessionAggregator.activeSessionCount {
                self.refreshUI()
            }
        }
        RunLoop.main.add(staleTimer, forMode: .common)
        ledStaleTimer = staleTimer
        let server = CtlSocketServer { [weak self] request in
            self?.handleCtlRequest(request) ?? .init(ok: false, error: L10n.text(.ctlAppNotReady))
        }
        server.start()
        ctlServer = server
    }

    private func handleCtlRequest(_ request: DialCtlProtocol.Request) -> DialCtlProtocol.Response {
        guard let renderer = ledRenderer else {
            return .init(ok: false, error: L10n.text(.ctlRendererNotReady))
        }
        switch request.command {
        case "led":
            guard let raw = request.state, let state = DialAgentState(rawValue: raw) else {
                return .init(ok: false, error: L10n.text(.ctlUnknownState) + (request.state ?? "nil"))
            }
            renderer.request(state)
            return .init(ok: true, state: state.rawValue)
        case "hook":
            guard let event = request.event else {
                return .init(ok: false, error: L10n.text(.ctlMissingEvent))
            }
            let dialect = request.dialect ?? "claude"
            guard let state = DialAgentEventMapper.state(
                agentDialect: dialect, event: event, when: request.when
            ) else {
                return .init(ok: true, state: renderer.state.rawValue)
            }
            let session = request.session ?? "default"
            let resolved = ledSessionAggregator.record(
                session: session, state: state, now: Date().timeIntervalSince1970,
                agent: request.agent
            )
            renderer.request(resolved)
            refreshUI()
            return .init(ok: true, state: resolved.rawValue)
        case "restore":
            renderer.shutdown()
            return .init(ok: true, state: "off")
        case "status":
            let details = ledSessionAggregator
                .activeSessions(now: Date().timeIntervalSince1970)
                .map { info in
                    DialCtlProtocol.Response.SessionDetail(
                        id: info.id, agent: info.agent, state: info.state.rawValue,
                        ageSeconds: Int(info.ageSeconds), winning: info.isWinning
                    )
                }
            return .init(ok: true, state: renderer.state.rawValue, sessions: details)
        default:
            return .init(ok: false, error: L10n.text(.ctlUnknownCommand) + request.command)
        }
    }

    private func loadConfiguration() {
        do {
            let url = try ConfigStore.defaultConfigURL()
            let store = ConfigStore(configURL: url)
            configuration = try store.loadOrCreate()
            let migratedKnob = configuration.restoreLegacyReservedKnobMappings()
            let needsInitialNativeBackup = configuration.offlineProfile == nil
            // One-time normalization: old configs may still carry the removed
            // "switchProfile" action on disk. It decodes as .none in memory;
            // rewrite the file once so the stale string does not linger.
            let rawContainsRemovedAction = (try? Data(contentsOf: url))
                .flatMap { String(data: $0, encoding: .utf8) }?
                .contains("switchProfile") ?? false
            if migratedKnob || needsInitialNativeBackup || rawContainsRemovedAction {
                if migratedKnob || needsInitialNativeBackup {
                    configuration.needsHardwareSync = true
                }
                try store.save(configuration)
            }
            needsHardwareSync = configuration.needsHardwareSync
            configStore = store
            configurationReady = true
        } catch {
            configurationReady = false
            notice = L10n.text(.noticeConfigReadFailed) + error.localizedDescription
        }
    }

    private func configureStatusItemAndPanel() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel(_:))
        self.statusItem = statusItem

        let settings = SettingsViewController(configuration: configuration)
        settings.onMappingChanged = { [weak self] profile, control, binding in
            guard let self else { return }
            guard !self.hardwareSyncInProgress else {
                self.refreshUI()
                return
            }
            let previousConfiguration = self.configuration
            var profileConfiguration = self.configuration[profile]
            profileConfiguration[control] = binding
            self.configuration[profile] = profileConfiguration
            guard self.persistConfiguration() else {
                self.configuration = previousConfiguration
                self.refreshUI()
                return
            }
            if case .preset(let action) = binding, action.isAppOnly {
                self.notice = L10n.text(.noticeAppOnlySaved)
            } else {
                self.notice = L10n.text(.noticeMappingSavedAuto)
            }
            self.refreshUI()
            // The device backup follows the edit automatically (debounced
            // so rapid successive changes coalesce into one write).
            if control.isNativeHardwareControl {
                self.configuration.needsHardwareSync = true
                self.needsHardwareSync = true
                self.scheduleAutoSync(delay: 1.5)
            }
        }
        settings.onQuit = {
            NSApplication.shared.terminate(nil)
        }
        settings.onShowAgentHooks = { [weak self] in
            self?.showAgentHooksWindow()
        }
        settings.onPreviewLedState = { [weak self] state in
            self?.previewLedState(state)
        }
        settings.onLightModeChanged = { [weak self] mode in
            self?.changeLightMode(mode)
        }
        settings.onGrantAccessibility = {
            PermissionGuide.requestAccessibility()
        }
        settings.onGrantInputMonitoring = {
            PermissionGuide.requestInputMonitoring()
        }
        settings.onShowGuide = { [weak self] in
            self?.showGuideWindow()
        }
        settingsViewController = settings

        let panel = DialPanelController(
            content: settings,
            statusButton: { [weak self] in self?.statusItem?.button }
        )
        panel.onShow = { [weak self] in
            self?.hardwareListener?.powerPollEveryNHeartbeats = 3
            self?.hardwareListener?.refreshPowerStatus()
        }
        panel.onClose = { [weak self] in
            self?.hardwareListener?.powerPollEveryNHeartbeats = 30
        }
        panelController = panel
    }

    // MARK: - Live power polling

    /// The AU05 does not push charge-state changes; the host must GET them.
    /// Originally the only GET triggers were connect/resume and opening the
    /// panel — so plugging in the charger showed nothing until the next
    /// click. Now: while the panel is open, a battery query rides every 3rd
    /// heartbeat (~2.4 s, feels live); while closed, every 30th (~24 s) so
    /// the menu-bar badge stays honest without meaningful extra traffic
    /// (the heartbeat itself already runs every 0.8 s). The cadence flip
    /// lives in the panel's onShow/onClose hooks.

    /// Panel LED preview: hold a state on the device, or return to live.
    /// Preview bypasses the session aggregator on purpose — it is a manual
    /// demonstration, not an agent event. Only meaningful in smart mode.
    private func previewLedState(_ state: DialAgentState?) {
        guard let renderer = ledRenderer, configuration.lightMode == .smart else { return }
        if let state {
            renderer.request(state)
        } else {
            let resolved = ledSessionAggregator.resolvedState(now: Date().timeIntervalSince1970)
            renderer.request(resolved)
        }
        settingsViewController?.currentLedState = renderer.state
    }

    /// Applies a light mode: static modes write their table once and suppress
    /// agent rendering; smart re-enables the engine and replays live state.
    private func applyLightMode(_ mode: DialLightMode) {
        guard let renderer = ledRenderer else { return }
        if let table = mode.staticTable {
            renderer.staticMode = true
            renderer.applyStatic(table)
        } else {
            renderer.staticMode = false
            let resolved = ledSessionAggregator.resolvedState(now: Date().timeIntervalSince1970)
            renderer.request(resolved)
        }
    }

    private func changeLightMode(_ mode: DialLightMode) {
        guard mode != configuration.lightMode else { return }
        let previous = configuration
        configuration.lightMode = mode
        guard persistConfiguration() else {
            configuration = previous
            refreshUI()
            return
        }
        applyLightMode(mode)
        refreshUI()
    }

    private func configureHardwareListener() {
        let listener = IOKitHardwareListener(
            eventHandler: { [weak self] deviceEvent, timestamp in
                self?.handle(deviceEvent, at: timestamp)
            },
            powerResponseHandler: { [weak self] response in
                guard let self else { return }
                self.devicePowerStatus.apply(response)
                if case .battery = response {
                    // Battery moved: flip the menu-bar badge (low ↔ charging
                    // ↔ normal) and, if the panel is open, its ring gauge —
                    // the user is watching it while plugging in the charger.
                    self.refreshStatusItem()
                    if self.panelController?.isVisible == true {
                        self.refreshUI()
                    }
                }
                if case let .standbyTime(seconds) = response {
                    self.applyPowerHandoffDecisions(
                        self.powerHandoffStateMachine.updateIdleInterval(
                            TimeInterval(seconds),
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                self.refreshUI()
            },
            noticeHandler: { [weak self] notice in
                guard let self else { return }
                if case let .standby(status) = notice {
                    self.devicePowerStatus.isStandby = status != 0
                }
                self.applyPowerHandoffDecisions(
                    self.powerHandoffStateMachine.noticeReceived(notice)
                )
                self.refreshUI()
            },
            powerSavingWakeHandler: { [weak self] in
                guard let self else { return }
                self.applyPowerHandoffDecisions(
                    self.powerHandoffStateMachine.wakeInputReceived()
                )
            },
            connectionHandler: { [weak self] connected in
                guard let self else { return }
                self.deviceConnected = connected
                if !connected {
                    self.deviceResponsive = true
                    self.devicePowerStatus = DialPowerSnapshot()
                    self.powerSaving = false
                    self.cancelPowerHandoff(
                        reason: .onlinePrerequisiteLost
                    )
                } else {
                    self.connectionRecoveryTimer?.invalidate()
                    self.connectionRecoveryTimer = nil
                    self.connectionRecoveryAttemptsRemaining = 0
                    self.applyPowerHandoffDecisions(
                        self.powerHandoffStateMachine.onlineStarted(
                            at: HIDMonotonicClock.now
                        )
                    )
                    // Device just appeared: finish any pending backup write.
                    if self.needsHardwareSync {
                        self.scheduleAutoSync(delay: 0.5)
                    }
                }
                if connected,
                   self.notice == L10n.text(.noticeDeviceRemoved)
                    || self.notice == L10n.text(.noticeDeviceRestarting)
                    || self.notice == L10n.text(.noticeWaitingDeviceReturn) {
                    self.notice = nil
                }
                self.refreshUI()
            },
            responsivenessHandler: { [weak self] responsive in
                guard let self else { return }
                self.deviceResponsive = responsive
                if !responsive {
                    // The last battery reading is a memory, not a measurement.
                    self.devicePowerStatus = DialPowerSnapshot()
                    self.cancelPowerHandoff(reason: .onlinePrerequisiteLost)
                }
                self.refreshUI()
            },
            failureHandler: { [weak self] error in
                guard let self else { return }
                let stopError = self.suspendEnhancedMode()
                self.notice = (stopError ?? error).localizedDescription
                self.refreshUI()
            },
            deviceRemovalHandler: { [weak self] in
                self?.handleDeviceRemoval()
            },
            shouldRemainOnline: { [weak self] in
                guard let self else { return false }
                return self.onlinePreflightIsValid
            }
        )
        hardwareListener = listener
    }

    private func configureLifecycleObservers() {
        let center = NSWorkspace.shared.notificationCenter

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopEnhancedMode(
                notice: L10n.text(.noticeMacSleeping)
            )
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopEnhancedMode(
                notice: L10n.text(.noticeMacShuttingDown)
            )
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeAfterUserActivityIfNeeded()
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard Self.isVendorApplication(notification) else { return }
            if self?.hardwareSyncInProgress == true {
                self?.vendorInterferedDuringHardwareSync = true
            }
            self?.ledRenderer?.suspendForVendor()
            self?.stopEnhancedMode(
                notice: L10n.text(.noticeStudioOpened)
            )
        })

        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard Self.isVendorApplication(notification) else { return }
            self?.resumeEnhancedModeIfSafe()
            self?.ledRenderer?.resume()
        })
    }

    private static func isVendorApplication(_ notification: Notification) -> Bool {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        return application?.bundleIdentifier == "ulanzi.UlanziStudio"
    }

    private func stopEnhancedMode(
        notice: String,
        reason: DialPowerHandoffSuspensionReason = .onlinePrerequisiteLost
    ) {
        let offlineError = suspendEnhancedMode(reason: reason)
        self.notice = offlineError?.localizedDescription ?? notice
        refreshUI()
    }

    private func suspendEnhancedMode(
        reason: DialPowerHandoffSuspensionReason = .onlinePrerequisiteLost
    ) -> Error? {
        cancelPowerHandoff(reason: reason)
        cancelPendingInput()
        let hadAttachedDevice = hardwareListener?.hasAttachedDevice == true
        let offlineError = hardwareListener?.stop()
        if offlineError != nil {
            offlineStateUnconfirmed = true
        } else if hadAttachedDevice {
            offlineStateUnconfirmed = false
        }
        listenerActive = false
        deviceConnected = false
        deviceResponsive = true
        devicePowerStatus = DialPowerSnapshot()
        powerSaving = false
        return offlineError
    }

    private func resumeEnhancedModeIfSafe() {
        guard !listenerActive,
              !hardwareSyncInProgress,
              !needsHardwareSync else { return }
        startHardwareListener(promptForPermission: false)
    }

    private func resumeAfterUserActivityIfNeeded() {
        // Opening the menu is not AU05 activity. While native power saving is
        // active, only a completed physical AU05 input should restore online
        // gestures; otherwise merely checking battery status wakes its lights.
        guard !powerSaving else { return }
        resumeEnhancedModeIfSafe()
    }

    private func applyPowerHandoffDecisions(
        _ decisions: [DialPowerHandoffDecision]
    ) {
        for decision in decisions {
            switch decision {
            case let .scheduleStandbyHandoff(deadline):
                powerHandoffTimer?.invalidate()
                let delay = max(0, deadline - HIDMonotonicClock.now)
                let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.powerHandoffTimer = nil
                    self.applyPowerHandoffDecisions(
                        self.powerHandoffStateMachine.standbyHandoffDeadlineReached(
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                powerHandoffTimer = timer
                RunLoop.main.add(timer, forMode: .common)

            case .cancelStandbyHandoff:
                powerHandoffTimer?.invalidate()
                powerHandoffTimer = nil

            case .handoffForStandby:
                guard listenerActive,
                      deviceConnected,
                      !hardwareSyncInProgress,
                      !needsHardwareSync else {
                    cancelPowerHandoff(reason: .onlinePrerequisiteLost)
                    return
                }
                cancelPendingInput()
                if let error = hardwareListener?.enterPowerSavingMode() {
                    let stopError = suspendEnhancedMode()
                    notice = (stopError ?? error).localizedDescription
                } else {
                    powerSaving = true
                    notice = L10n.text(.noticePowerSaving)
                }
                refreshUI()

            case .resumeOnline:
                guard powerSaving else { continue }
                if let error = hardwareListener?.resumeFromPowerSaving() {
                    let stopError = suspendEnhancedMode()
                    logger.error(
                        "Controller wake connection was stale: \(error.localizedDescription, privacy: .public)"
                    )
                    if let stopError {
                        logger.error(
                            "Stale connection cleanup reported: \(stopError.localizedDescription, privacy: .public)"
                        )
                    }
                    notice = L10n.text(.noticeDeviceRestarting)
                    scheduleConnectionRecovery()
                } else {
                    powerSaving = false
                    devicePowerStatus.isStandby = false
                    if notice == L10n.text(.noticePowerSaving) {
                        notice = nil
                    }
                    applyPowerHandoffDecisions(
                        powerHandoffStateMachine.onlineStarted(
                            at: HIDMonotonicClock.now
                        )
                    )
                }
                refreshUI()
            }
        }
    }

    private func cancelPowerHandoff(reason: DialPowerHandoffSuspensionReason) {
        powerHandoffTimer?.invalidate()
        powerHandoffTimer = nil
        _ = powerHandoffStateMachine.suspendAutomaticResume(reason: reason)
    }

    private func startHardwareListener(promptForPermission: Bool) {
        cancelPendingInput()


        guard configurationReady else {
            listenerActive = false
            deviceConnected = false
            notice = L10n.text(.noticeConfigUnusable)
            refreshUI()
            return
        }

        accessibilityGranted = AccessibilityAccess.isTrusted(
            promptForPermission: promptForPermission
        )
        DebugLog.log("startHardwareListener: accessibilityGranted=\(accessibilityGranted) vendorNotRunning=\(vendorApplicationIsNotRunning)")
        guard accessibilityGranted else {
            listenerActive = false
            deviceConnected = false
            notice = L10n.text(.noticeNeedAccessibility)
            refreshUI()
            return
        }

        guard vendorApplicationIsNotRunning else {
            listenerActive = false
            deviceConnected = false
            notice = L10n.text(.noticeStudioRunning)
            refreshUI()
            return
        }

        do {
            try validateAllProfilesForOnlineMode()
        } catch {
            listenerActive = false
            deviceConnected = false
            notice = L10n.text(.noticeGestureInvalid) + error.localizedDescription
            refreshUI()
            return
        }

        do {
            try hardwareListener?.start(promptForPermission: promptForPermission)
            listenerActive = true
            DebugLog.log("startHardwareListener: listener started OK")
            if notice == L10n.text(.noticeNeedAccessibility)
                || notice?.hasPrefix(L10n.text(.noticeListenFailed)) == true {
                notice = nil
            }
        } catch {
            listenerActive = false
            deviceConnected = false
            notice = L10n.text(.noticeListenFailed) + error.localizedDescription
        logger.error(
            "Listener startup failed: \(error.localizedDescription, privacy: .public)"
        )
        DebugLog.log("startHardwareListener FAILED: \(error.localizedDescription)")
        }

        refreshUI()
    }

    private func scheduleConnectionRecovery() {
        guard !deviceConnected,
              !needsHardwareSync else { return }
        connectionRecoveryAttemptsRemaining = 3
        scheduleNextConnectionRecovery()
    }

    private func scheduleNextConnectionRecovery() {
        connectionRecoveryTimer?.invalidate()
        guard connectionRecoveryAttemptsRemaining > 0,
              !deviceConnected else { return }

        let timer = Timer(timeInterval: 2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.connectionRecoveryTimer = nil
            guard !self.deviceConnected,
                  !self.needsHardwareSync else { return }

            self.connectionRecoveryAttemptsRemaining -= 1
            self.logger.notice(
                "Rebuilding AU05 connection; attempts remaining=\(self.connectionRecoveryAttemptsRemaining, privacy: .public)"
            )
            if let error = self.suspendEnhancedMode() {
                // A fully powered-off controller can make the final offline
                // write fail. The manager was still closed, so continue with
                // a fresh HID session instead of requiring an app restart.
                self.logger.error(
                    "Connection reset cleanup reported: \(error.localizedDescription, privacy: .public)"
                )
            }
            self.startHardwareListener(promptForPermission: false)
            guard self.listenerActive, !self.deviceConnected else { return }
            if self.connectionRecoveryAttemptsRemaining > 0 {
                self.scheduleNextConnectionRecovery()
            } else {
                self.notice = L10n.text(.noticeWaitingDeviceReturn)
                self.refreshUI()
            }
        }
        connectionRecoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resetKnobPressState() {
        knobSinglePressTimer?.invalidate()
        knobSinglePressTimer = nil
        knobPressStateMachine.reset()
    }

    private func cancelPendingInput() {
        resetKnobPressState()
        actionPerformer.releaseAll()
    }

    private func handleDeviceRemoval() {
        cancelPowerHandoff(reason: .onlinePrerequisiteLost)
        cancelPendingInput()
        offlineStateUnconfirmed = false
        deviceConnected = false
        devicePowerStatus = DialPowerSnapshot()
        powerSaving = false
        notice = L10n.text(.noticeDeviceRemoved)
        refreshUI()
    }

    private func handle(_ deviceEvent: DeviceEvent, at timestamp: TimeInterval) {
        guard listenerActive,
              deviceConnected,
              !hardwareSyncInProgress,
              !needsHardwareSync else { return }
        applyPowerHandoffDecisions(
            powerHandoffStateMachine.deviceInput(at: timestamp)
        )
        let eventTime = String(format: "%.6f", timestamp)
        DebugLog.log("HID event: \(deviceEvent)")
        logger.notice(
            "HID event: \(String(describing: deviceEvent), privacy: .public) time=\(eventTime, privacy: .public)"
        )
        switch deviceEvent {
        case let .key(control: .knobPress, phase: phase):
            handleKnobPress(phase, at: timestamp)
        case let .key(control: control, phase: phase):
            handleOrdinaryControl(control, phase: phase)
        }
    }

    private func handleOrdinaryControl(_ control: InputControl, phase: KeyPhase) {
        let binding = configuration[configuration.activeProfile][control]
        guard binding.holdsSyntheticKey else {
            guard phase == .down else { return }
            do {
                // AU05 controls are macro triggers. Send one complete tap on
                // down so a crash can never leave a synthetic modifier held.
                try actionPerformer.tap(binding, for: control)
                recordUsage(control)
            } catch {
                notice = L10n.text(.noticeActionFailed) + error.localizedDescription
                refreshUI()
            }
            return
        }
        // Push-to-talk actions: hold the synthetic key between device down/up.
        do {
            if phase == .down {
                DebugLog.log("voice: press (FN down)")
                try actionPerformer.press(binding, for: control)
                recordUsage(control)
            } else {
                DebugLog.log("voice: release (FN up)")
                actionPerformer.release(for: control)
            }
        } catch {
            DebugLog.log("voice FAILED: \(error.localizedDescription)")
            notice = L10n.text(.noticeActionFailed) + error.localizedDescription
            refreshUI()
        }
    }

    private func handleKnobPress(_ phase: KeyPhase, at timestamp: TimeInterval) {
        switch phase {
        case .down:
            applyKnobPressDecisions(knobPressStateMachine.pressDown(at: timestamp))
        case .up:
            applyKnobPressDecisions(knobPressStateMachine.pressUp(at: timestamp))
        }
    }

    private func applyKnobPressDecisions(_ decisions: [KnobPressDecision]) {
        for decision in decisions {
            applyKnobPressDecision(decision)
        }
    }

    private func applyKnobPressDecision(_ decision: KnobPressDecision) {
        logger.notice("Knob decision: \(String(describing: decision), privacy: .public)")
        switch decision {
        case let .scheduleSinglePress(delay):
            knobSinglePressTimer?.invalidate()
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.knobSinglePressTimer = nil
                if let decision = self.knobPressStateMachine.singlePressTimerFired() {
                    self.applyKnobPressDecision(decision)
                }
            }
            knobSinglePressTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        case .cancelPendingSinglePress:
            knobSinglePressTimer?.invalidate()
            knobSinglePressTimer = nil
        case .performSinglePress:
            performGestureBinding(for: .knobPress)
        case .performDoublePress:
            performGestureBinding(for: .knobDoublePress)
        }
    }

    private func performGestureBinding(for control: InputControl) {
        let binding = configuration[configuration.activeProfile][control]
        do {
            try actionPerformer.tap(binding, for: control)
            recordUsage(control)
        } catch {
            notice = L10n.text(.noticeActionFailed) + error.localizedDescription
            refreshUI()
        }
    }

    // MARK: - Automatic device backup (no manual write button)

    /// Debounced auto-sync. Coalesces rapid mapping edits into one write;
    /// skips while a write is in flight or the device is absent (the
    /// connect handler re-triggers when it appears).
    private func scheduleAutoSync(delay: TimeInterval) {
        autoSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoSyncWorkItem = nil
            guard self.configurationReady,
                  self.needsHardwareSync,
                  !self.hardwareSyncInProgress,
                  self.deviceConnected else { return }
            self.syncHardware(profileID: self.configuration.activeProfile)
        }
        autoSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func syncHardware(profileID: ProfileID) {
        guard configurationReady else {
            notice = L10n.text(.noticeConfigUnusableNoWrite)
            refreshUI()
            return
        }

        guard !hardwareSyncInProgress else { return }

        if let vendor = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.vendorBundleIdentifier
        ).first {
            exitVendorThenSync(vendor: vendor, profileID: profileID)
            return
        }

        continueSyncHardware(profileID: profileID)
    }

    /// Ulanzi Studio holds the AU05 in native mode and conflicts with any
    /// write. Quit it on the user's behalf (graceful first, then force) and
    /// only ask for manual action if it survives both.
    private func exitVendorThenSync(vendor: NSRunningApplication, profileID: ProfileID) {
        hardwareSyncInProgress = true
        vendorInterferedDuringHardwareSync = false
        notice = L10n.text(.noticeStudioQuitting)
        refreshUI()
        vendor.terminate()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var deadline = Date().addingTimeInterval(4)
            while Date() < deadline, !vendor.isTerminated {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if !vendor.isTerminated {
                vendor.forceTerminate()
                deadline = Date().addingTimeInterval(2)
                while Date() < deadline, !vendor.isTerminated {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            let vendorExited = vendor.isTerminated

            DispatchQueue.main.async {
                guard let self else { return }
                self.hardwareSyncInProgress = false
                guard vendorExited else {
                    self.notice = L10n.text(.noticeStudioNotQuit)
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = L10n.text(.alertStudioNotQuitTitle)
                    alert.informativeText = L10n.text(.alertStudioNotQuitBody)
                    alert.addButton(withTitle: L10n.text(.alertOK))
                    alert.runModal()
                    self.refreshUI()
                    return
                }
                self.continueSyncHardware(profileID: profileID)
            }
        }
    }

    private func continueSyncHardware(profileID: ProfileID) {

        let profile = configuration[profileID]
        let hasAppOnlyBindings = profile.indexedControlBindings.contains {
            if case .preset(let action) = $0.binding { return action.isAppOnly }
            return false
        }

        if !needsHardwareSync {
            let previousConfiguration = configuration
            configuration.needsHardwareSync = true
            guard persistConfiguration() else {
                configuration = previousConfiguration
                refreshUI()
                return
            }
            needsHardwareSync = true
        }

        hardwareSyncInProgress = true
        vendorInterferedDuringHardwareSync = false
        if let error = suspendEnhancedMode() {
            hardwareSyncInProgress = false
            notice = L10n.text(.noticeWriteFailed) + error.localizedDescription
            refreshUI()
            return
        }
        notice = L10n.text(.noticeWritingDevice)
        refreshUI()

        let configurator = hardwareConfigurator
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try configurator.apply(profile: profile)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                self.hardwareSyncInProgress = false

                switch result {
                case .success:
                    self.offlineStateUnconfirmed = false
                    if self.vendorInterferedDuringHardwareSync
                        || !self.vendorApplicationIsNotRunning {
                        self.configuration.needsHardwareSync = true
                        self.needsHardwareSync = true
                        self.notice = L10n.text(.noticeStudioDuringWrite)
                        self.presentSyncFailureAlert(
                            L10n.text(.noticeStudioDuringWrite)
                        )
                    } else if let markerSaveError = self.completeHardwareSync(profileID: profileID) {
                        self.notice = L10n.text(.noticeWroteMarkerSaveFailed) + markerSaveError
                    } else if hasAppOnlyBindings {
                        self.notice = L10n.text(.noticeWroteAppOnly)
                    } else {
                        self.notice = L10n.text(.noticeWrote)
                    }
                    self.logger.notice(
                        "Hardware profile \(profileID.rawValue, privacy: .public) written successfully"
                    )
                    if !self.needsHardwareSync,
                       !self.listenerActive,
                       true {
                        self.startHardwareListener(promptForPermission: true)
                    }
                case let .failure(error):
                    if let configurationError = error as? IOKitHardwareConfiguratorError {
                        switch configurationError {
                        case .offlineWriteFailed:
                            self.offlineStateUnconfirmed = true
                            self.notice = L10n.text(.noticeSyncAborted) + error.localizedDescription + L10n.text(.noticeSyncAbortedShort)
                        case .reportWriteFailed:
                            self.offlineStateUnconfirmed = false
                            self.notice = L10n.text(.noticeSyncFailedPartial) + error.localizedDescription + L10n.text(.noticeSyncFailed)
                        default:
                            self.notice = L10n.text(.noticeSyncAborted) + error.localizedDescription
                        }
                    } else {
                        self.notice = L10n.text(.noticeSyncFailedPartial) + error.localizedDescription
                    }
                    self.presentSyncFailureAlert(self.notice ?? L10n.text(.alertSyncFailedFallback))
                    self.logger.error(
                        "Hardware profile write failed: \(error.localizedDescription, privacy: .public)"
                    )
                }

                self.refreshUI()
            }
        }
    }

    private static let vendorBundleIdentifier = "ulanzi.UlanziStudio"

    /// User-visible guidance when the offline write does not complete. The
    /// button no longer confirms before writing; failing after the fact is
    /// when the user needs a dialog.
    private func presentSyncFailureAlert(_ guidance: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text(.alertSyncIncompleteTitle)
        alert.informativeText = guidance
        alert.addButton(withTitle: L10n.text(.alertOK))
        alert.runModal()
    }

    private var vendorApplicationIsNotRunning: Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.vendorBundleIdentifier
        ).isEmpty
    }

    private var onlinePreflightIsValid: Bool {
        guard configurationReady,
              configuration.offlineProfile != nil,
              !needsHardwareSync,
              vendorApplicationIsNotRunning,
              IOHIDListenAccess.isGranted,
              AccessibilityAccess.isTrusted(promptForPermission: false) else {
            return false
        }
        return (try? validateAllProfilesForOnlineMode()) != nil
    }

    private func validateAllProfilesForOnlineMode() throws {
        try actionPerformer.validate(profile: configuration.profileA)
        try actionPerformer.validate(profile: configuration.profileB)
    }

    private func completeHardwareSync(profileID: ProfileID) -> String? {
        guard let configStore else {
            return L10n.text(.syncConfigLocationUnavailable)
        }

        let previousOfflineProfile = configuration.offlineProfile
        configuration.offlineProfile = profileID
        configuration.needsHardwareSync = false
        do {
            try configStore.save(configuration)
            needsHardwareSync = false
            return nil
        } catch {
            configuration.offlineProfile = previousOfflineProfile
            configuration.needsHardwareSync = true
            needsHardwareSync = true
            return error.localizedDescription
        }
    }

    @discardableResult
    private func persistConfiguration() -> Bool {
        guard let configStore else {
            notice = L10n.text(.noticeConfigLocationUnavailable)
            return false
        }

        do {
            try configStore.save(configuration)
            if notice == L10n.text(.noticeConfigLocationUnavailable)
                || notice?.hasPrefix(L10n.text(.noticeConfigSaveFailed)) == true
                || notice?.hasPrefix(L10n.text(.noticeConfigReadFailed)) == true {
                notice = nil
            }
            return true
        } catch {
            notice = L10n.text(.noticeConfigSaveFailed) + error.localizedDescription
            return false
        }
    }

    private func refreshUI() {
        refreshStatusItem()
        settingsViewController?.update(
            configuration: configuration,
            listenerActive: listenerActive,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: IOHIDListenAccess.isGranted,
            deviceConnected: deviceConnected,
            deviceResponsive: deviceResponsive,
            powerStatus: devicePowerStatus,
            powerSaving: powerSaving,
            hardwareSyncInProgress: hardwareSyncInProgress,
            notice: notice,
            usageStats: usageStats,
            activeSessions: ledSessionAggregator.activeSessions(now: Date().timeIntervalSince1970)
        )
        if let renderer = ledRenderer {
            settingsViewController?.currentLedState = renderer.state
        }
        // The heartbeat calls refreshUI continuously, which gives the panel
        // a free anchor check: if a menu-bar manager moved the status item
        // (or the icon was hidden entirely), the panel follows or closes
        // instead of hovering in the wrong place.
        panelController?.repositionIfNeeded()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }

        let state = DialStatusBar.resolve(
            deviceConnected: deviceConnected,
            deviceResponsive: deviceResponsive,
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: IOHIDListenAccess.isGranted,
            battery: devicePowerStatus.battery
        )
        let batteryDescription = devicePowerStatus.battery.map {
            L10n.text(.batterySuffix) + "\($0.percent)%"
        } ?? ""
        let accessibleName = "DialPilot · " + Self.statusBarDescription(state) + batteryDescription
        let darkMenuBar = Self.menuBarIsDark()
        let image = DialStatusIcon.image(for: state, darkMenuBar: darkMenuBar) ?? NSImage(
            systemSymbolName: "dial.medium",
            accessibilityDescription: nil
        )

        button.toolTip = accessibleName
        button.setAccessibilityLabel(accessibleName)

        if let image {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.imagePosition = .noImage
            button.title = "VK"
        }
    }

    private static func statusBarDescription(_ state: DialStatusBarState) -> String {
        switch state {
        case .disconnected: return L10n.text(.statusDisconnected)
        case .needsPermission: return L10n.text(.statusNeedsPermission)
        case .lowBattery: return L10n.text(.statusLowBattery)
        case .charging: return L10n.text(.statusCharging)
        case .normal: return L10n.text(.statusNormal)
        }
    }

    /// The menu bar follows the system appearance (it can stay dark even
    /// in light mode with "dark menu bar" wallpapers). Badge variants are
    /// non-template, so we must pick the body color ourselves.
    private static func menuBarIsDark() -> Bool {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func observeMenuBarAppearance() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatusItem()
        }
    }

    // MARK: - Usage statistics

    private func loadUsageStats() {
        do {
            let url = try DialUsageStats.defaultURL()
            usageStatsURL = url
            usageStats = DialUsageStats.load(from: url)
        } catch {
            logger.error("Usage stats location unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Records one performed control event. Called from the input paths
    /// only — never from preview/ctl. Persistence is debounced 2 s so a
    /// knob spin (dozens of detents) writes once, not dozens of times.
    private func recordUsage(_ control: InputControl) {
        usageStats.record(
            control: control,
            on: DialUsageStats.dayKey(for: Date())
        )
        scheduleUsageSave()
    }

    private func scheduleUsageSave() {
        usageSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushUsageStats()
        }
        usageSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    private func flushUsageStats() {
        usageSaveWorkItem?.cancel()
        usageSaveWorkItem = nil
        guard let url = usageStatsURL else { return }
        do {
            try usageStats.save(to: url)
        } catch {
            logger.error("Usage stats save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard statusItem?.button != nil, let panelController else { return }
        if panelController.isVisible {
            panelController.dismiss()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let panelController, !panelController.isVisible else { return }
        resumeAfterUserActivityIfNeeded()
        // Re-check permissions every time the panel opens: the user may have
        // just granted them in System Settings and come back.
        accessibilityGranted = AccessibilityAccess.isTrusted(promptForPermission: false)
        refreshUI()
        panelController.present()
        hardwareListener?.refreshPowerStatus()
    }
}
