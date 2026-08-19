import Foundation

public enum ConfigPermissions {
    public static let directory = 0o700
    public static let file = 0o600

    public static func apply(directory: URL, file: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.directory],
            ofItemAtPath: directory.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: Self.file],
            ofItemAtPath: file.path
        )
    }
}

public struct SettingsStore: Sendable {
    public static let configDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config", isDirectory: true)
        .appendingPathComponent("runbar", isDirectory: true)

    public static let configFile: URL = configDirectory.appendingPathComponent("config.json")

    private static let defaultsKey = "runbar.settings"

    public init() {}

    public func load() -> AppSettings {
        if let settings = loadFromDefaults() {
            return settings.sanitized()
        }
        if let settings = loadFromFile() {
            let sanitized = settings.sanitized()
            saveToDefaults(sanitized)
            return sanitized
        }
        let settings = AppSettings.default
        save(settings)
        return settings
    }

    public func save(_ settings: AppSettings) {
        let sanitized = settings.sanitized()
        saveToDefaults(sanitized)
        saveToFile(sanitized)
    }

    private func loadFromDefaults() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func saveToDefaults(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    private func loadFromFile() -> AppSettings? {
        guard let data = try? Data(contentsOf: Self.configFile) else {
            return nil
        }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func saveToFile(_ settings: AppSettings) {
        do {
            try FileManager.default.createDirectory(at: Self.configDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: Self.configFile, options: .atomic)
            try ConfigPermissions.apply(directory: Self.configDirectory, file: Self.configFile)
        } catch {
            // Local config is optional; UserDefaults remains the source of truth.
        }
    }
}
