import Foundation

public final class ConfigStore {
    public let configURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// Test override for the predecessor config location.
    private let legacyConfigURLOverride: URL?

    public init(
        configURL: URL,
        fileManager: FileManager = .default,
        legacyConfigURL: URL? = nil
    ) {
        self.configURL = configURL
        self.fileManager = fileManager
        self.legacyConfigURLOverride = legacyConfigURL

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    public static func defaultConfigURL(fileManager: FileManager = .default) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        return applicationSupport
            .appendingPathComponent("DialPilot", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public func loadOrCreate() throws -> AppConfiguration {
        guard fileManager.fileExists(atPath: configURL.path) else {
            // One-time migration from the predecessor app's config, so an
            // upgrade keeps the user's mappings and offline-profile marker.
            let legacy = try legacyConfigURLOverride
                ?? Self.legacyConfigURL(fileManager: fileManager)
            if let legacy, fileManager.fileExists(atPath: legacy.path) {
                let data = try Data(contentsOf: legacy)
                let configuration = try decoder.decode(AppConfiguration.self, from: data)
                try save(configuration)
                return configuration
            }
            let configuration = AppConfiguration.default
            try save(configuration)
            return configuration
        }

        let data = try Data(contentsOf: configURL)
        return try decoder.decode(AppConfiguration.self, from: data)
    }

    /// Predecessor location (VibeKey Lite). Read once on first launch;
    /// the legacy file is left untouched as a fallback.
    private static func legacyConfigURL(fileManager: FileManager) throws -> URL? {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return applicationSupport
            .appendingPathComponent("VibeKey Lite", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public func save(_ configuration: AppConfiguration) throws {
        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let data = try encoder.encode(configuration)
        try data.write(to: configURL, options: .atomic)
    }
}
