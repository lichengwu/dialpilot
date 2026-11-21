import AppKit

/// Opens the exact System Settings pane for a permission, and triggers the
/// native prompt where the API supports it. Keeps the user one click away
/// from granting instead of hunting through Settings.
enum PermissionGuide {
    /// Privacy & Security → Accessibility
    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Privacy & Security → Input Monitoring
    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    /// Shows the native Accessibility prompt (the system dialog with the
    /// "Open System Settings" button), then opens the pane as a fallback.
    static func requestAccessibility() {
        _ = AccessibilityAccess.isTrusted(promptForPermission: true)
        openAccessibilitySettings()
    }

    /// Triggers the Input Monitoring request; if already denied, opens the
    /// pane so the user can flip the switch manually.
    static func requestInputMonitoring() {
        do {
            try IOHIDListenAccess.ensure(promptForPermission: true)
        } catch {
            openInputMonitoringSettings()
        }
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}