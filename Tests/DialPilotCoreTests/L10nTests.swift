import XCTest
@testable import DialPilotCore

final class L10nTests: XCTestCase {
    override func tearDown() {
        L10n.language = .system
        super.tearDown()
    }

    func testResolveChineseVariants() {
        for lang in ["zh-Hans-CN", "zh-Hant-TW", "zh-CN", "zh", "ZH-hans"] {
            XCTAssertEqual(DialLanguage.resolve(preferredLanguages: [lang]), .chinese, lang)
        }
    }

    func testResolveNonChineseDefaultsEnglish() {
        for lang in ["en-US", "ja-JP", "fr-FR", "de-DE", "ko-KR"] {
            XCTAssertEqual(DialLanguage.resolve(preferredLanguages: [lang]), .english, lang)
        }
        XCTAssertEqual(DialLanguage.resolve(preferredLanguages: []), .english)
    }

    func testOnlyTopLanguageMatters() {
        // System list order is preference order; a later zh does not win.
        XCTAssertEqual(
            DialLanguage.resolve(preferredLanguages: ["en-US", "zh-Hans-CN"]),
            .english
        )
        XCTAssertEqual(
            DialLanguage.resolve(preferredLanguages: ["zh-Hans-CN", "en-US"]),
            .chinese
        )
    }

    func testKeyTableReturnsBothLanguages() {
        L10n.language = .english
        XCTAssertEqual(L10n.text(.quit), "Quit")
        XCTAssertEqual(L10n.text(.lightModeSmart), "Smart")
        L10n.language = .chinese
        XCTAssertEqual(L10n.text(.quit), "退出")
        XCTAssertEqual(L10n.text(.lightModeSmart), "智能")
    }

    func testProfileDisplayNamesFollowLanguage() {
        L10n.language = .english
        XCTAssertEqual(ProfileID.b.displayName, "System")
        XCTAssertEqual(InputControl.knobPress.displayName, "Knob press")
        L10n.language = .chinese
        XCTAssertEqual(ProfileID.b.displayName, "系统")
        XCTAssertEqual(InputControl.knobPress.displayName, "旋钮单按")
    }

    func testCategoryDisplayNamesFollowLanguage() {
        L10n.language = .english
        XCTAssertEqual(KeyActionCategory.basic.displayName, "Basic")
        XCTAssertEqual(KeyActionCategory.media.displayName, "Media")
        L10n.language = .chinese
        XCTAssertEqual(KeyActionCategory.basic.displayName, "基本")
        // rawValue stays stable regardless of language (config/test contract).
        XCTAssertEqual(KeyActionCategory.functionKeys.rawValue, "F1–F12")
    }

    func testAllGuideKeysNonEmptyInBothLanguages() {
        let guideKeys: [L10n.Key] = [
            .guideIdleWhen, .guideIdleHow, .guideThinkingWhen, .guideThinkingHow,
            .guideWorkingWhen, .guideWorkingHow, .guideAttentionWhen, .guideAttentionHow,
            .guideNotificationWhen, .guideNotificationHow, .guideErrorWhen, .guideErrorHow,
            .guideSweepingWhen, .guideSweepingHow,
        ]
        for language in DialLanguage.allCases {
            L10n.language = language
            for key in guideKeys {
                XCTAssertFalse(L10n.text(key).isEmpty, "\(key) in \(language)")
            }
        }
    }
}

final class DialLightModeTests: XCTestCase {
    func testSmartIsDefaultAndDecodesFromLegacyConfig() throws {
        XCTAssertEqual(AppConfiguration.default.lightMode, .smart)
        let legacy = """
        {"activeProfile":"a","profileA":{},"profileB":{},"needsHardwareSync":true}
        """
        let config = try JSONDecoder().decode(AppConfiguration.self, from: Data(legacy.utf8))
        XCTAssertEqual(config.lightMode, .smart)
    }

    func testLightModeRoundTrip() throws {
        var config = AppConfiguration.default
        config.lightMode = .allOn
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(decoded.lightMode, .allOn)
    }

    func testStaticTables() throws {
        // All On: global mode 1, brighter all-on brightness.
        let allOn = try XCTUnwrap(DialLightMode.allOn.staticTable)
        XCTAssertEqual(allOn.mode, 1)
        XCTAssertEqual(allOn.allOnBrightness, 15)
        try DialLedControl.validate(allOn)
        // Off: host LEDs off, work mode.
        let off = try XCTUnwrap(DialLightMode.off.staticTable)
        XCTAssertEqual(off.mode, 2)
        for led in 1...3 {
            XCTAssertEqual(off.leds[led].workType, 0)
        }
        try DialLedControl.validate(off)
        // Smart has no static table — it renders through the engine.
        XCTAssertNil(DialLightMode.smart.staticTable)
    }

    func testDisplayNamesFollowLanguage() {
        L10n.language = .english
        XCTAssertEqual(DialLightMode.allOn.displayName, "All On")
        XCTAssertEqual(DialLightMode.off.displayName, "Off")
        L10n.language = .chinese
        XCTAssertEqual(DialLightMode.allOn.displayName, "全开")
        XCTAssertEqual(DialLightMode.off.displayName, "关闭")
        L10n.language = .system
    }
}