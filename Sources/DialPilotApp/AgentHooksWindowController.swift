import AppKit
import DialPilotCore

/// "Agent 灯效接入" window: a list of agent targets with detection status
/// and one-click install/uninstall. Hard gate: absent software is never
/// configured — the user is told to install it first (user requirement
/// QwenWork uses the enterprise-console HTTP flow.
final class AgentHooksWindowController: NSWindowController {
    /// Injected by AppDelegate: start/stop the loopback listener and query
    /// its running state. The window never owns the socket itself.
    var onStartQwenWorkListener: (() -> String?)?   // returns token on success
    var onStopQwenWorkListener: (() -> Void)?
    var isQwenWorkListenerRunning: (() -> Bool)?
    var qwenWorkSnippets: (() -> [String: String])?

    private let tableView = NSTableView()
    private var detections: [DialHookInstaller.Detection] = []
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private var qwenWorkListenerActive = false

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text(.hooksWindowTitle)
        self.init(window: window)
        buildUI()
        refresh()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let intro = NSTextField(wrappingLabelWithString: L10n.text(.hooksIntro))
        intro.font = .systemFont(ofSize: 11)
        intro.textColor = .secondaryLabelColor

        // Column widths sum to the table width (560 − 2×16 margins − 2×1
        // intercell gaps = 526) so nothing overflows the right edge and the
        // header dividers line up with the cell content below them.
        let nameColumn = NSTableColumn(identifier: .init("name"))
        nameColumn.title = "Agent"
        nameColumn.width = 186
        nameColumn.minWidth = 150
        let statusColumn = NSTableColumn(identifier: .init("status"))
        statusColumn.title = L10n.text(.hooksColStatus)
        statusColumn.width = 190
        statusColumn.minWidth = 150
        let actionColumn = NSTableColumn(identifier: .init("action"))
        actionColumn.title = L10n.text(.hooksColAction)
        actionColumn.width = 150
        actionColumn.minWidth = 110
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(statusColumn)
        tableView.addTableColumn(actionColumn)
        tableView.headerView = NSTableHeaderView()
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 1, height: 0)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3

        let refreshButton = NSButton(title: L10n.text(.hooksRefresh), target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded
        let closeButton = NSButton(title: L10n.text(.hooksClose), target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded
        let buttons = NSStackView(views: [refreshButton, NSView(), closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [intro, scroll, statusLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func closeWindow() {
        window?.close()
    }

    @objc private func refresh() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        detections = DialAgentTarget.allCases.map { target in
            var detection = DialHookInstaller.detect(
                target: target, homeDirectory: home, pathDirectories: pathDirectories
            )
            if target == .qwenwork {
                // QwenWork is a desktop app; detect the bundle.
                detection.detected = FileManager.default.fileExists(
                    atPath: "/Applications/QwenWork.app"
                ) || FileManager.default.fileExists(
                    atPath: NSHomeDirectory() + "/Applications/QwenWork.app"
                )
                detection.installed = isQwenWorkListenerRunning?() ?? qwenWorkListenerActive
            }
            return detection
        }
        tableView.reloadData()
    }

    private func ctlPath() -> String {
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/dialpilotctl").path
        if FileManager.default.isExecutableFile(atPath: bundlePath) {
            return "\"\(bundlePath)\""
        }
        return "\"\(Bundle.main.bundleURL.path)/Contents/MacOS/dialpilotctl\""
    }

    private func performInstall(_ target: DialAgentTarget) {
        guard let detection = detections.first(where: { $0.target == target }) else { return }
        guard detection.detected else {
            let alert = NSAlert()
            alert.messageText = L10n.text(.hooksNotDetectedTitle) + target.displayName
            alert.informativeText = L10n.text(.hooksInstallFirst)
            alert.addButton(withTitle: L10n.text(.openDownloadPage))
            alert.addButton(withTitle: L10n.text(.cancel))
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: target.downloadURL) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if target == .qwenwork {
            showQwenWorkGuide()
            return
        }
        if target == .dsh {
            performDshInstall(uninstall: false)
            return
        }
        guard target.usesClaudeJSONContract, let relative = target.settingsRelativePath else {
            // Unreachable for the current target list (qwenwork/dsh handled
            // above); kept as a defensive guard for future targets.
            statusLabel.stringValue = target.displayName + L10n.text(.hooksUnsupportedLocal)
            return
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURL = home.appendingPathComponent(relative)
        let existing = try? Data(contentsOf: settingsURL)
        do {
            let merged = try DialHookInstaller.mergedSettings(
                existing: existing, target: target, ctlPath: ctlPath()
            )
            try writeWithBackup(existing: existing, new: merged, at: settingsURL)
            let written = try Data(contentsOf: settingsURL)
            let root = try JSONSerialization.jsonObject(with: written) as? [String: Any] ?? [:]
            guard DialHookInstaller.containsMarker(in: root) else {
                statusLabel.stringValue = L10n.text(.hooksReadbackFailed)
                return
            }
            if target == .codex {
                let configURL = home.appendingPathComponent(".codex/config.toml")
                let configExisting = try? String(contentsOf: configURL, encoding: .utf8)
                if let updated = DialHookInstaller.codexConfigEnablingHooks(existing: configExisting) {
                    try writeWithBackup(
                        existing: configExisting.map { Data($0.utf8) },
                        new: Data(updated.utf8), at: configURL
                    )
                }
                statusLabel.stringValue = L10n.text(.hooksCodexConnected)
            } else {
                statusLabel.stringValue = target.displayName + L10n.text(.hooksConnectedRestart)
            }
        } catch {
            statusLabel.stringValue = L10n.text(.hooksInstallFailed) + error.localizedDescription
        }
        refresh()
    }

    private func performUninstall(_ target: DialAgentTarget) {
        if target == .qwenwork {
            onStopQwenWorkListener?()
            qwenWorkListenerActive = false
            statusLabel.stringValue = L10n.language == .chinese ? "已停止本机监听。请到企业管理后台（安全管控 → Hooks 规则）清空对应事件的 dialpilot 配置。" : "Listener stopped. Clear the dialpilot rules in the enterprise console (Security Controls → Hooks Rules)."
            refresh()
            return
        }
        if target == .dsh {
            performDshInstall(uninstall: true)
            return
        }
        guard let relative = target.settingsRelativePath else { return }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relative)
        guard let existing = try? Data(contentsOf: settingsURL) else {
            statusLabel.stringValue = L10n.text(.hooksNoConfig)
            return
        }
        do {
            guard let unmerged = try DialHookInstaller.unmergedSettings(existing: existing) else {
                statusLabel.stringValue = L10n.text(.hooksNoMarker)
                return
            }
            try writeWithBackup(existing: existing, new: unmerged, at: settingsURL)
            statusLabel.stringValue = target.displayName + L10n.text(.hooksRemoved)
        } catch {
            statusLabel.stringValue = L10n.text(.hooksUninstallFailed) + error.localizedDescription
        }
        refresh()
    }

    private func performDshInstall(uninstall: Bool) {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(DialAgentTarget.dsh.settingsRelativePath!)
        let existing = try? String(contentsOf: settingsURL, encoding: .utf8)
        do {
            if uninstall {
                guard let existing,
                      let unmerged = DialHookInstaller.unmergedDshPatch(existing: existing) else {
                    statusLabel.stringValue = L10n.text(.hooksNoMarker)
                    return
                }
                try writeWithBackup(existing: Data(existing.utf8), new: Data(unmerged.utf8), at: settingsURL)
                statusLabel.stringValue = L10n.text(.hooksDshRemoved)
            } else {
                let merged = DialHookInstaller.mergedDshPatch(existing: existing, ctlPath: ctlPath())
                try writeWithBackup(existing: existing.map { Data($0.utf8) }, new: Data(merged.utf8), at: settingsURL)
                let written = try String(contentsOf: settingsURL, encoding: .utf8)
                guard written.contains("- id: \(DialHookInstaller.dshMarkerID)") else {
                    statusLabel.stringValue = L10n.text(.hooksDshReadbackFailed)
                    return
                }
                statusLabel.stringValue = L10n.text(.hooksDshConnected)
            }
        } catch {
            statusLabel.stringValue = L10n.text(.hooksDshWriteFailed) + error.localizedDescription
        }
        refresh()
    }

    private func writeWithBackup(existing: Data?, new: Data, at url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing {
            let backup = url.appendingPathExtension("bak-dialpilot-\(Int(Date().timeIntervalSince1970))")
            try existing.write(to: backup)
        }
        try new.write(to: url, options: .atomic)
    }

    private func showQwenWorkGuide() {
        // Install = start the loopback listener, then hand over console JSON.
        guard let token = onStartQwenWorkListener?() else {
            let alert = NSAlert()
            alert.messageText = L10n.text(.qwenListenerFailedTitle)
            alert.informativeText = L10n.text(.qwenListenerFailedBody)
            alert.runModal()
            return
        }
        qwenWorkListenerActive = true
        let snippets = qwenWorkSnippets?() ?? DialQwenWorkHookHandler.consoleSnippets(token: token)
        let text = DialQwenWorkHookHandler.wiredEvents
            .compactMap { event in snippets[event].map { "// \(event)\n\($0)" } }
            .joined(separator: "\n\n")
        let alert = NSAlert()
        alert.messageText = L10n.text(.qwenGuideTitle)
        alert.informativeText = L10n.text(.qwenGuideBody)
        alert.addButton(withTitle: L10n.text(.qwenCopyConfig))
        alert.addButton(withTitle: L10n.text(.hooksClose))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            statusLabel.stringValue = L10n.text(.qwenCopied)
        } else {
            statusLabel.stringValue = L10n.text(.qwenListenerStarted)
        }
        refresh()
    }
}

extension AgentHooksWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        detections.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let detection = detections[row]
        switch tableColumn?.identifier.rawValue {
        case "name":
            let label = NSTextField(labelWithString: detection.target.displayName)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            return padded(label, leading: 8, trailing: 4)
        case "status":
            let label: NSTextField
            if detection.installed {
                label = NSTextField(labelWithString: L10n.text(.hooksConnected))
                label.textColor = PanelTheme.ok
            } else if detection.detected {
                label = NSTextField(labelWithString: L10n.text(.hooksInstalledNotConnected))
                label.textColor = .secondaryLabelColor
            } else {
                label = NSTextField(labelWithString: L10n.text(.hooksNotDetected))
                label.textColor = PanelTheme.warn
            }
            label.font = PanelTheme.captionFont
            return padded(label, leading: 4, trailing: 4)
        case "action":
            let button: NSButton
            if detection.installed {
                button = NSButton(title: L10n.text(.hooksUninstall), target: self, action: #selector(uninstallClicked(_:)))
                button.contentTintColor = .secondaryLabelColor
            } else {
                button = NSButton(title: L10n.text(.hooksInstall), target: self, action: #selector(installClicked(_:)))
                button.isEnabled = detection.detected
                button.toolTip = detection.detected ? L10n.text(.hooksInstallTooltip) : L10n.text(.hooksInstallFirstTooltip)
            }
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.tag = row
            button.font = PanelTheme.captionFont
            // Center the button in its column with breathing room on both
            // sides — it used to sit flush against the right edge.
            button.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(button)
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                button.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 8),
                button.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -8),
            ])
            return container
        default:
            return nil
        }
    }

    /// Wraps a label so cell text starts at a fixed inset instead of
    /// hugging the column divider (the left "empty band" in the screenshot
    /// was the header inset not matching the cell inset).
    private func padded(_ label: NSTextField, leading: CGFloat, trailing: CGFloat) -> NSView {
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: leading),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -trailing),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    @objc private func installClicked(_ sender: NSButton) {
        guard detections.indices.contains(sender.tag) else { return }
        performInstall(detections[sender.tag].target)
    }

    @objc private func uninstallClicked(_ sender: NSButton) {
        guard detections.indices.contains(sender.tag) else { return }
        performUninstall(detections[sender.tag].target)
    }
}