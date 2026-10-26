import Foundation

/// Persisted user settings. Custom decoding keeps old files loadable after a schema bump.
public struct Settings: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 6
    public static let hoverDelayRange: ClosedRange<Double> = 0.05...1.5
    public static let collapseDelayRange: ClosedRange<Double> = 0.1...2.0
    public static let agentRetentionRange: ClosedRange<Double> = 1...120
    /// New installs start with what Brim is for at a glance; existing files keep their own list.
    public static let defaultEnabledModules = ["media", "clock"]

    public var schemaVersion: Int = Settings.currentSchemaVersion
    /// Seconds the pointer must rest on the notch before the panel opens.
    public var hoverDelay: Double = 0.15
    /// Seconds the pointer must leave the panel before it collapses.
    public var collapseDelay: Double = 0.4
    /// False opens the panel only on a click; hovering then does nothing.
    public var opensOnHover: Bool = true
    /// Widen the collapsed notch to show live content (playing media, an agent that needs you).
    public var showLiveActivity: Bool = true
    /// The system login item is the source of truth; this mirrors it for persistence and diagnostics.
    public var launchAtLogin: Bool = false
    /// Enabled module IDs in display order. Unknown IDs are ignored by the registry.
    public var enabledModules: [String] = Settings.defaultEnabledModules
    /// Which displays get a panel. Replaces schema 5's `showOnNonNotchedDisplays` toggle.
    public var displayMode: DisplayMode = .all
    /// Bundle identifier of the player to follow, or nil for whatever macOS reports. Choosing Spotify or
    /// Music enables the optional Apple Events path; the adapter alone needs no setting.
    public var preferredPlayerBundleID: String?
    /// Minutes a done or failed agent session stays in the panel before it is pruned.
    public var agentFinishedRetentionMinutes: Double = 10
    /// Post a local notification when an agent newly needs input or fails while the panel is closed.
    public var agentNotificationsEnabled: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? defaults.schemaVersion

        let hover = try container.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? defaults.hoverDelay
        hoverDelay = min(max(hover, Self.hoverDelayRange.lowerBound), Self.hoverDelayRange.upperBound)
        let collapse = try container.decodeIfPresent(Double.self, forKey: .collapseDelay) ?? defaults.collapseDelay
        collapseDelay = min(max(collapse, Self.collapseDelayRange.lowerBound), Self.collapseDelayRange.upperBound)
        opensOnHover = try container.decodeIfPresent(Bool.self, forKey: .opensOnHover) ?? defaults.opensOnHover
        showLiveActivity = try container.decodeIfPresent(Bool.self, forKey: .showLiveActivity)
            ?? defaults.showLiveActivity

        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        enabledModules = try container.decodeIfPresent([String].self, forKey: .enabledModules) ?? defaults.enabledModules
        // An unknown value from a newer build falls back to the default instead of failing the whole file.
        displayMode = (try? container.decodeIfPresent(DisplayMode.self, forKey: .displayMode)) ?? defaults.displayMode
        preferredPlayerBundleID = try container.decodeIfPresent(String.self, forKey: .preferredPlayerBundleID)
        let retention = try container.decodeIfPresent(Double.self, forKey: .agentFinishedRetentionMinutes)
            ?? defaults.agentFinishedRetentionMinutes
        agentFinishedRetentionMinutes = retention.isFinite
            ? min(max(retention, Self.agentRetentionRange.lowerBound), Self.agentRetentionRange.upperBound)
            : defaults.agentFinishedRetentionMinutes
        agentNotificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .agentNotificationsEnabled)
            ?? defaults.agentNotificationsEnabled
    }
}
