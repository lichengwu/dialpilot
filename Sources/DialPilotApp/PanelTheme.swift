import AppKit
import DialPilotCore

/// Shared visual language for DialPilot's popover and windows.
/// Light/dark adaptive via semantic NSColors; one accent (system blue)
/// for interactive emphasis, green/orange reserved for status semantics.
enum PanelTheme {
    static let accent = NSColor.controlAccentColor
    static let ok = NSColor.systemGreen
    static let warn = NSColor.systemOrange
    static let danger = NSColor.systemRed

    static let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: 12)
    static let captionFont = NSFont.systemFont(ofSize: 11)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// Section header: small caps-feel label with secondary color.
    static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = captionFont
        label.textColor = .secondaryLabelColor
        return label
    }

    /// A hairline separator that adapts to appearance.
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    /// Rounded card container for grouping related controls.
    static func card() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.06).cgColor
        return view
    }

    /// Status dot + text row. Color carries the semantics; text stays readable.
    static func statusRow(dot: NSColor, text: String) -> NSStackView {
        let dotView = NSView()
        dotView.wantsLayer = true
        dotView.layer?.backgroundColor = dot.cgColor
        dotView.layer?.cornerRadius = 3.5
        dotView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: 7),
            dotView.heightAnchor.constraint(equalToConstant: 7),
        ])
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = captionFont
        label.textColor = .labelColor
        let row = NSStackView(views: [dotView, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }
}