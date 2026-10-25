import Foundation

public enum SettingsMigrator {
    public enum MigrationError: Error { case notAnObject }

    /// Each step upgrades a raw JSON object from version N to N+1.
    static let steps: [Int: (inout [String: Any]) -> Void] = [
        0: { _ in }, // pre-versioned files only gain the schemaVersion key
        1: { _ in }, // schema 2 adds preferredPlayerBundleID; nil is the automatic default
    ]

    public static func migrate(_ data: Data) throws -> Settings {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MigrationError.notAnObject
        }
        var version = object["schemaVersion"] as? Int ?? 0
        while version < Settings.currentSchemaVersion {
            steps[version]?(&object)
            version += 1
            object["schemaVersion"] = version
        }
        let migrated = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Settings.self, from: migrated)
    }
}

public final class JSONSettingsStore: SettingsPersisting {
    private let fileURL: URL

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brim", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public init(fileURL: URL = JSONSettingsStore.defaultURL) {
        self.fileURL = fileURL
    }

    public func load() -> Settings {
        guard let data = try? Data(contentsOf: fileURL) else { return Settings() }
        do {
            return try SettingsMigrator.migrate(data)
        } catch {
            Log.settings.error("Unreadable settings, resetting: \(error.localizedDescription)")
            // Never silently destroy a user's file; keep it next to the fresh one for diagnosis.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("settings.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return Settings()
        }
    }

    public func save(_ settings: Settings) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var current = settings
            current.schemaVersion = Settings.currentSchemaVersion
            try encoder.encode(current).write(to: fileURL, options: .atomic)
        } catch {
            Log.settings.error("Failed to save settings: \(error.localizedDescription)")
        }
    }
}
