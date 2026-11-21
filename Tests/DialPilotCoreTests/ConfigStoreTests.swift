import Foundation
import XCTest
@testable import DialPilotCore

final class ConfigStoreTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testLoadOrCreateWritesReadableDefaults() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let store = ConfigStore(configURL: configURL, legacyConfigURL: temporaryDirectory.appendingPathComponent("no-legacy.json"))

        let configuration = try store.loadOrCreate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        XCTAssertEqual(configuration.activeProfile, .a)
        XCTAssertNil(configuration.offlineProfile)
        XCTAssertEqual(configuration[.a][.knobLeft], .preset(.downArrow))
        XCTAssertEqual(configuration[.a][.knobPress], .preset(.selectAll))
        // Single profile: double-press defaults to "do nothing".
        XCTAssertEqual(configuration[.a][.knobDoublePress], .preset(.none))

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL))
        let dictionary = try XCTUnwrap(json as? [String: Any])
        XCTAssertNotNil(dictionary["profileA"] as? [String: Any])
    }

    func testDefaultProfileMatchesAILayout() {
        let configuration = AppConfiguration.default

        XCTAssertEqual(configuration[.a][.knobLeft], .preset(.downArrow))
        XCTAssertEqual(configuration[.a][.knobPress], .preset(.selectAll))
        XCTAssertEqual(configuration[.a][.knobDoublePress], .preset(.none))
        XCTAssertEqual(configuration[.a][.knobRight], .preset(.upArrow))
        XCTAssertEqual(configuration[.a][.topButton], .preset(.optionKey))
        XCTAssertEqual(configuration[.a][.middleButton], .preset(.returnKey))
        XCTAssertEqual(configuration[.a][.bottomButton], .preset(.tab))
        XCTAssertTrue(configuration.needsHardwareSync)
        XCTAssertNil(configuration.offlineProfile)
        XCTAssertEqual(configuration.activeProfile, .a)
        XCTAssertTrue(configuration.appProfileMapping.isEmpty)
    }

    func testMigrationPullsActiveProfileBackToAAndClearsMapping() {
        var configuration = AppConfiguration.default
        configuration.activeProfile = .b
        configuration.appProfileMapping = ["com.example.app": .b]
        configuration.offlineProfile = .b

        XCTAssertTrue(configuration.restoreLegacyReservedKnobMappings())
        XCTAssertEqual(configuration.activeProfile, .a)
        XCTAssertTrue(configuration.appProfileMapping.isEmpty)
        XCTAssertNil(configuration.offlineProfile)
        XCTAssertFalse(configuration.restoreLegacyReservedKnobMappings())
    }

    func testRemovedSwitchProfileActionDecodesAsNone() throws {
        // Old configs bound knobDoublePress to "switchProfile". The action
        // no longer exists; the slot must degrade to .none, not crash.
        let json = """
        {
          "activeProfile": "a",
          "profileA": { "knobDoublePress": "switchProfile", "knobPress": "selectAll" },
          "profileB": {}
        }
        """
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded[.a][.knobDoublePress], .preset(.none))
        XCTAssertEqual(decoded[.a][.knobPress], .preset(.selectAll))
    }

    func testRoundTripsCustomizedProfile() throws {
        let configURL = temporaryDirectory.appendingPathComponent("nested/config.json")
        let store = ConfigStore(configURL: configURL, legacyConfigURL: temporaryDirectory.appendingPathComponent("no-legacy.json"))
        var expected = AppConfiguration.default
        var profileA = expected[.a]
        profileA[.topButton] = .preset(.f1)
        profileA[.middleButton] = .preset(.fnDoubleTap)
        expected[.a] = profileA

        try store.save(expected)
        let actual = try store.loadOrCreate()

        XCTAssertEqual(actual, expected)
    }

    func testMissingMappingDecodesAsNone() throws {
        let json = """
        {
          "activeProfile": "a",
          "profileA": { "knobLeft": "leftArrow" },
          "profileB": {}
        }
        """
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))

        XCTAssertEqual(decoded[.a][.knobLeft], .preset(.leftArrow))
        XCTAssertEqual(decoded[.a][.knobRight], .preset(.none))
        XCTAssertEqual(decoded[.a][.knobDoublePress], .preset(.none))
        XCTAssertEqual(decoded[.b][.topButton], .preset(.none))
        XCTAssertTrue(decoded.needsHardwareSync)
    }

    func testCompletedNativeProfileSyncRoundTrips() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let store = ConfigStore(configURL: configURL, legacyConfigURL: temporaryDirectory.appendingPathComponent("no-legacy.json"))
        var expected = AppConfiguration.default
        expected.needsHardwareSync = false
        expected.offlineProfile = .a

        try store.save(expected)

        XCTAssertFalse(try store.loadOrCreate().needsHardwareSync)
        XCTAssertEqual(try store.loadOrCreate().offlineProfile, .a)
    }

    func testMissingOfflineProfileForcesHardwareSync() throws {
        let json = """
        {
          "activeProfile": "a",
          "profileA": {},
          "profileB": {},
          "needsHardwareSync": false
        }
        """

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(decoded.offlineProfile)
        XCTAssertTrue(decoded.needsHardwareSync)
    }

    func testRoundTripsRecordedNativeShortcut() throws {
        let shortcut = try NativeShortcut(
            entries: [.init(pageAndSign: 0x03, value: 0x04)],
            displayName: "左 Option"
        )
        var expected = AppConfiguration.default
        var profileA = expected[.a]
        profileA[.topButton] = .shortcut(shortcut)
        expected[.a] = profileA

        let encoded = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: encoded)

        XCTAssertEqual(decoded, expected)
    }

    func testInvalidJSONIsNotOverwritten() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let invalidData = Data("not-json".utf8)
        try invalidData.write(to: configURL)
        let store = ConfigStore(configURL: configURL, legacyConfigURL: temporaryDirectory.appendingPathComponent("no-legacy.json"))

        XCTAssertThrowsError(try store.loadOrCreate())
        XCTAssertEqual(try Data(contentsOf: configURL), invalidData)
    }

    func testMigratesLegacyConfigOnFirstLaunch() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let legacyURL = temporaryDirectory.appendingPathComponent("legacy.json")
        var legacy = AppConfiguration.default
        legacy.offlineProfile = .a
        legacy.needsHardwareSync = false
        try JSONEncoder().encode(legacy).write(to: legacyURL)

        let store = ConfigStore(configURL: configURL, legacyConfigURL: legacyURL)
        let loaded = try store.loadOrCreate()

        XCTAssertEqual(loaded.activeProfile, .a)
        XCTAssertEqual(loaded.offlineProfile, .a)
        // Migrated config is persisted at the new location.
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))
        // Legacy file is left untouched as a fallback.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        // Second launch reads the new location, not the legacy one.
        try Data().write(to: legacyURL.appendingPathExtension("x"))
        let second = try ConfigStore(configURL: configURL, legacyConfigURL: legacyURL).loadOrCreate()
        XCTAssertEqual(second.activeProfile, .a)
    }

    func testNoLegacyConfigCreatesDefaults() throws {
        let configURL = temporaryDirectory.appendingPathComponent("config.json")
        let missingLegacy = temporaryDirectory.appendingPathComponent("absent.json")
        let store = ConfigStore(configURL: configURL, legacyConfigURL: missingLegacy)
        let loaded = try store.loadOrCreate()
        XCTAssertEqual(loaded, AppConfiguration.default)
    }
}