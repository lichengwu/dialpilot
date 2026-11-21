import Foundation

public enum ProfileID: String, CaseIterable, Codable, Sendable {
    case a
    case b

    public var displayName: String {
        switch self {
        case .a: L10n.text(.profileAI)
        case .b: L10n.text(.profileSystem)
        }
    }

    public var toggled: ProfileID {
        self == .a ? .b : .a
    }
}

public enum InputControl: String, CaseIterable, Codable, CodingKey, Sendable {
    case knobPress
    case knobDoublePress
    case knobLeft
    case knobRight
    case topButton
    case middleButton
    case bottomButton

    public var displayName: String {
        switch self {
        case .knobPress: L10n.language == .chinese ? "旋钮单按" : "Knob press"
        case .knobDoublePress: L10n.language == .chinese ? "旋钮双按" : "Knob double"
        case .knobLeft: L10n.language == .chinese ? "旋钮向左" : "Knob left"
        case .knobRight: L10n.language == .chinese ? "旋钮向右" : "Knob right"
        case .topButton: L10n.language == .chinese ? "上键" : "Top button"
        case .middleButton: L10n.language == .chinese ? "中键" : "Middle button"
        case .bottomButton: L10n.language == .chinese ? "下键" : "Bottom button"
        }
    }

    public var isNativeHardwareControl: Bool {
        self != .knobDoublePress
    }

}

public enum KeyPhase: Equatable, Sendable {
    case down
    case up
}

public enum DeviceEvent: Equatable, Sendable {
    case key(control: InputControl, phase: KeyPhase)
}

public enum KeyAction: String, CaseIterable, Codable, Sendable {
    case none
    case space
    case returnKey
    case escape
    case tab
    case fnDoubleTap
    case voiceInput
    case optionKey
    case rightOptionKey
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case deleteBackward
    case deleteForward
    case home
    case end
    case pageUp
    case pageDown
    case f1
    case f2
    case f3
    case f4
    case f5
    case f6
    case f7
    case f8
    case f9
    case f10
    case f11
    case f12
    case selectAll
    case copy
    case paste
    case cut
    case undo
    case redo
    case save
    case appSwitcher
    case spotlight
    case screenshot
    case missionControl
    case volumeUp
    case volumeDown
    case mute
    case brightnessUp
    case brightnessDown
    case previousTrack
    case nextTrack
    case playPause

    public var displayName: String {
        let zh = L10n.language == .chinese
        switch self {
        case .none: return zh ? "不做事" : "Do nothing"
        case .space: return "Space"
        case .returnKey: return "Return"
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .fnDoubleTap: return zh ? "Fn 按两次（App 开启时）" : "Fn double-tap (app running)"
        case .voiceInput: return zh ? "语音输入（按住说话，自动切微信输入法）" : "Voice input (hold to talk, WeChat IME)"
        case .optionKey: return zh ? "左 Option" : "Left Option"
        case .rightOptionKey: return zh ? "右 Option" : "Right Option"
        case .leftArrow: return zh ? "方向键 ←" : "Arrow ←"
        case .rightArrow: return zh ? "方向键 →" : "Arrow →"
        case .upArrow: return zh ? "方向键 ↑" : "Arrow ↑"
        case .downArrow: return zh ? "方向键 ↓" : "Arrow ↓"
        case .deleteBackward: return "Delete／Backspace"
        case .deleteForward: return "Forward Delete"
        case .home: return "Home"
        case .end: return "End"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        case .selectAll: return zh ? "⌘A（全选）" : "⌘A (Select All)"
        case .copy: return zh ? "⌘C（复制）" : "⌘C (Copy)"
        case .paste: return zh ? "⌘V（粘贴）" : "⌘V (Paste)"
        case .cut: return zh ? "⌘X（剪切）" : "⌘X (Cut)"
        case .undo: return zh ? "⌘Z（撤销）" : "⌘Z (Undo)"
        case .redo: return zh ? "⌘⇧Z（重做）" : "⌘⇧Z (Redo)"
        case .save: return zh ? "⌘S（保存）" : "⌘S (Save)"
        case .appSwitcher: return zh ? "⌘Tab（切换 App）" : "⌘Tab (App Switcher)"
        case .spotlight: return "⌘Space (Spotlight)"
        case .screenshot: return zh ? "⌘⇧5（截图）" : "⌘⇧5 (Screenshot)"
        case .missionControl: return "⌃↑ (Mission Control)"
                case .volumeUp: return zh ? "音量提高" : "Volume Up"
        case .volumeDown: return zh ? "音量降低" : "Volume Down"
        case .mute: return zh ? "静音" : "Mute"
        case .brightnessUp: return zh ? "亮度提高" : "Brightness Up"
        case .brightnessDown: return zh ? "亮度降低" : "Brightness Down"
        case .previousTrack: return zh ? "上一首" : "Previous Track"
        case .nextTrack: return zh ? "下一首" : "Next Track"
        case .playPause: return zh ? "播放／暂停" : "Play / Pause"
        }
    }

    public var category: KeyActionCategory {
        switch self {
        case .none, .space, .returnKey, .escape, .tab, .fnDoubleTap,
             .voiceInput, .optionKey, .rightOptionKey:
            .basic
        case .leftArrow, .rightArrow, .upArrow, .downArrow,
             .deleteBackward, .deleteForward, .home, .end, .pageUp, .pageDown:
            .navigation
        case .f1, .f2, .f3, .f4, .f5, .f6,
             .f7, .f8, .f9, .f10, .f11, .f12:
            .functionKeys
        case .selectAll, .copy, .paste, .cut, .undo, .redo, .save:
            .editing
        case .appSwitcher, .spotlight, .screenshot, .missionControl:
            .system
        case .volumeUp, .volumeDown, .mute, .brightnessUp, .brightnessDown,
             .previousTrack, .nextTrack, .playPause:
            .media
        }
    }

    /// App-only actions are performed by DialPilot while it is running.
    /// The AU05 firmware cannot store them in the six offline slots, so a
    /// native sync writes an empty slot for them instead of failing.
    public var isAppOnly: Bool {
        self == .fnDoubleTap || self == .voiceInput
    }

    /// Push-to-talk actions press a synthetic key on device key-down and hold
    /// it until the device key-up, instead of sending one complete tap on down.
    public var holdsSyntheticKeyUntilRelease: Bool {
        self == .voiceInput
    }
}

public enum KeyActionCategory: String, CaseIterable, Sendable {
    case basic = "基本"
    case navigation = "导航"
    case functionKeys = "F1–F12"
    case editing = "编辑"
    case system = "系统"
    case media = "媒体"

    /// Localized heading for menus (rawValue stays stable for tests/config).
    public var displayName: String {
        let zh = L10n.language == .chinese
        switch self {
        case .basic: return zh ? "基本" : "Basic"
        case .navigation: return zh ? "导航" : "Navigation"
        case .functionKeys: return "F1–F12"
        case .editing: return zh ? "编辑" : "Editing"
        case .system: return zh ? "系统" : "System"
        case .media: return zh ? "媒体" : "Media"
        }
    }
}

public enum ControlBinding: Codable, Equatable, Sendable {
    case preset(KeyAction)
    case shortcut(NativeShortcut)

    private enum CodingKeys: String, CodingKey {
        case type
        case shortcut
    }

    private enum Kind: String, Codable {
        case shortcut
    }

    public init(from decoder: Decoder) throws {
        // A plain string is a preset action. Unknown / removed actions
        // (e.g. "switchProfile") degrade to .none instead of failing the
        // whole config — the slot becomes "do nothing", rebinding is easy.
        if let single = try? decoder.singleValueContainer(),
           let raw = try? single.decode(String.self) {
            self = .preset(KeyAction(rawValue: raw) ?? .none)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .shortcut:
            self = .shortcut(try container.decode(NativeShortcut.self, forKey: .shortcut))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case let .preset(action):
            var container = encoder.singleValueContainer()
            try container.encode(action)
        case let .shortcut(shortcut):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(Kind.shortcut, forKey: .type)
            try container.encode(shortcut, forKey: .shortcut)
        }
    }

    public var displayName: String {
        switch self {
        case let .preset(action): action.displayName
        case let .shortcut(shortcut): shortcut.displayName
        }
    }

    public var holdsSyntheticKey: Bool {
        if case .preset(let action) = self {
            return action.holdsSyntheticKeyUntilRelease
        }
        return false
    }
}

public struct ProfileConfiguration: Codable, Equatable, Sendable {
    private var mappings: [InputControl: ControlBinding]

    public init(mappings: [InputControl: ControlBinding] = [:]) {
        self.mappings = mappings
    }

    public subscript(control: InputControl) -> ControlBinding {
        get { mappings[control] ?? .preset(.none) }
        set { mappings[control] = newValue }
    }

    /// Equality is by effective binding: an absent control and an explicit
    /// `.none` are the same thing ("do nothing"). Without this, a decoded
    /// config (all seven controls materialized) would never equal a
    /// freshly-built one (sparse map), breaking round-trip assertions.
    public static func == (lhs: ProfileConfiguration, rhs: ProfileConfiguration) -> Bool {
        InputControl.allCases.allSatisfy { lhs[$0] == rhs[$0] }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: InputControl.self)
        var decoded: [InputControl: ControlBinding] = [:]

        for control in InputControl.allCases {
            decoded[control] = try container.decodeIfPresent(
                ControlBinding.self,
                forKey: control
            ) ?? .preset(.none)
        }

        mappings = decoded
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: InputControl.self)

        for control in InputControl.allCases {
            try container.encode(self[control], forKey: control)
        }
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var activeProfile: ProfileID
    public var offlineProfile: ProfileID?
    public var profileA: ProfileConfiguration
    public var profileB: ProfileConfiguration
    public var needsHardwareSync: Bool
    /// M1: frontmost-app bundleID → profile. Empty = feature off.
    /// Unmapped apps keep the current profile (no fallback switching).
    public var appProfileMapping: [String: ProfileID]
    /// Light behavior: allOn/off mirror native global modes; smart follows
    /// agent events. Defaults to smart; old configs decode as smart.
    public var lightMode: DialLightMode

    public init(
        activeProfile: ProfileID = .a,
        offlineProfile: ProfileID? = nil,
        profileA: ProfileConfiguration = .init(),
        profileB: ProfileConfiguration = .init(),
        needsHardwareSync: Bool = true,
        appProfileMapping: [String: ProfileID] = [:],
        lightMode: DialLightMode = .smart
    ) {
        self.activeProfile = activeProfile
        self.offlineProfile = offlineProfile
        self.profileA = profileA
        self.profileB = profileB
        self.needsHardwareSync = needsHardwareSync
        self.appProfileMapping = appProfileMapping
        self.lightMode = lightMode
    }

    private enum CodingKeys: String, CodingKey {
        case activeProfile
        case offlineProfile
        case profileA
        case profileB
        case needsHardwareSync
        case appProfileMapping
        case lightMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeProfile = try container.decode(ProfileID.self, forKey: .activeProfile)
        offlineProfile = try container.decodeIfPresent(ProfileID.self, forKey: .offlineProfile)
        profileA = try container.decode(ProfileConfiguration.self, forKey: .profileA)
        profileB = try container.decode(ProfileConfiguration.self, forKey: .profileB)
        // Configurations written before this marker existed must complete one
        // full native six-slot write before online gestures may start safely.
        let decodedNeedsHardwareSync = try container.decodeIfPresent(
            Bool.self,
            forKey: .needsHardwareSync
        ) ?? true
        // An offline profile is proof that a complete six-slot native backup
        // finished. Never trust an old/partial "false" marker without it.
        needsHardwareSync = offlineProfile == nil ? true : decodedNeedsHardwareSync
        // Configs written before M1 simply have no mapping: feature stays off.
        appProfileMapping = try container.decodeIfPresent(
            [String: ProfileID].self,
            forKey: .appProfileMapping
        ) ?? [:]
        // Configs written before light modes existed default to smart.
        lightMode = try container.decodeIfPresent(
            DialLightMode.self,
            forKey: .lightMode
        ) ?? .smart
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(activeProfile, forKey: .activeProfile)
        try container.encodeIfPresent(offlineProfile, forKey: .offlineProfile)
        try container.encode(profileA, forKey: .profileA)
        try container.encode(profileB, forKey: .profileB)
        try container.encode(needsHardwareSync, forKey: .needsHardwareSync)
        try container.encode(appProfileMapping, forKey: .appProfileMapping)
        try container.encode(lightMode, forKey: .lightMode)
    }

    public subscript(profile: ProfileID) -> ProfileConfiguration {
        get {
            switch profile {
            case .a: profileA
            case .b: profileB
            }
        }
        set {
            switch profile {
            case .a: profileA = newValue
            case .b: profileB = newValue
            }
        }
    }

    public static var `default`: AppConfiguration {
        var profileA = ProfileConfiguration()
        profileA[.knobPress] = .preset(.selectAll)
        profileA[.knobDoublePress] = .preset(.none)
        profileA[.knobLeft] = .preset(.downArrow)
        profileA[.knobRight] = .preset(.upArrow)
        profileA[.topButton] = .preset(.optionKey)
        profileA[.middleButton] = .preset(.returnKey)
        profileA[.bottomButton] = .preset(.tab)

        // Single-profile product: profileB is retained only so old
        // configs decode; it is never shown, switched to, or written.
        return AppConfiguration(
            activeProfile: .a,
            profileA: profileA
        )
    }

    /// One-time migrations that must leave the six native slots usable.
    ///
    /// The single-profile design removed the System profile and the
    /// `switchProfile` action. Old configs that bound a control to it fail to
    /// decode that binding and fall back to `.none` (see ControlBinding.init).
    /// A config whose activeProfile is `.b` must be pulled back to `.a`, and
    /// any auto-switch mapping is cleared — the feature is gone. The marker
    /// is reset so the device gets one clean rewrite of the single profile.
    @discardableResult
    public mutating func restoreLegacyReservedKnobMappings() -> Bool {
        var changed = false

        if activeProfile != .a {
            activeProfile = .a
            changed = true
        }
        if !appProfileMapping.isEmpty {
            appProfileMapping = [:]
            changed = true
        }

        if changed {
            offlineProfile = nil
        }

        return changed
    }
}
