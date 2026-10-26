import Foundation

/// Persisted user settings. Custom decoding keeps old files loadable after a schema bump.
public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3
    public static let hoverDelayRange: ClosedRange<Double> = 0.05...1.5
    public static let collapseDelayRange: ClosedRange<Double> = 0.1...2.0
    public static let agentRetentionRange: ClosedRange<Double> = 1...120
    public static let defaultEnabledModules = ["clock"]

    public var schemaVersion: Int = Settings.currentSchemaVersion
    /// Seconds the pointer must rest on the notch before a peek appears.
    public var hoverDelay: Double = 0.15
    /// Seconds the pointer must leave the panel before it collapses.
    public var collapseDelay: Double = 0.4
    /// The system login item is the source of truth; this mirrors it for persistence and diagnostics.
    public var launchAtLogin: Bool = false
    /// Enabled module IDs in display order. Unknown IDs are ignored by the registry.
    public var enabledModules: [String] = Settings.defaultEnabledModules
    /// Show the slim handle and panel on displays without a notch.
    public var showOnNonNotchedDisplays: Bool = true
    /// Bundle identifier of the player to follow, or nil for whatever macOS reports. Choosing Spotify or
    /// Music enables the optional Apple Events path; the adapter alone needs no setting.
    public var preferredPlayerBundleID: String?
    /// Minutes a done or failed agent session stays in the panel before it is pruned.
    public var agentFinishedRetentionMinutes: Double = 10

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? defaults.schemaVersion

        let hover = try container.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? defaults.hoverDelay
        hoverDelay = min(max(hover, Self.hoverDelayRange.lowerBound), Self.hoverDelayRange.upperBound)
        let collapse = try container.decodeIfPresent(Double.self, forKey: .collapseDelay) ?? defaults.collapseDelay
        collapseDelay = min(max(collapse, Self.collapseDelayRange.lowerBound), Self.collapseDelayRange.upperBound)

        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        enabledModules = try container.decodeIfPresent([String].self, forKey: .enabledModules) ?? defaults.enabledModules
        showOnNonNotchedDisplays = try container.decodeIfPresent(Bool.self, forKey: .showOnNonNotchedDisplays)
            ?? defaults.showOnNonNotchedDisplays
        preferredPlayerBundleID = try container.decodeIfPresent(String.self, forKey: .preferredPlayerBundleID)
        let retention = try container.decodeIfPresent(Double.self, forKey: .agentFinishedRetentionMinutes)
            ?? defaults.agentFinishedRetentionMinutes
        agentFinishedRetentionMinutes = retention.isFinite
            ? min(max(retention, Self.agentRetentionRange.lowerBound), Self.agentRetentionRange.upperBound)
            : defaults.agentFinishedRetentionMinutes
    }
}
