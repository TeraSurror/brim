import AppKit
import Combine
import Foundation

public enum SettingsTab: String, CaseIterable, Sendable {
    case general, media, agents, modules, about
}

/// Shared state for the panel and the settings window. Saves on every settings change, then lets the
/// registry bring module activation in line.
@MainActor
public final class AppModel: ObservableObject {
    @Published public var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            syncModules()
            if settings.preferredPlayerBundleID != oldValue.preferredPlayerBundleID {
                syncPreferredPlayer()
            }
            if settings.agentFinishedRetentionMinutes != oldValue.agentFinishedRetentionMinutes {
                syncAgentRetention()
            }
            if settings.agentNotificationsEnabled != oldValue.agentNotificationsEnabled {
                syncAgentNotifications()
            }
            if settings.showLiveActivity != oldValue.showLiveActivity {
                syncLiveActivity()
            }
        }
    }

    @Published public private(set) var launchAtLogin: Bool
    @Published public var launchAtLoginError: String?
    @Published public private(set) var activeModules: [any BrimModule] = []
    @Published public private(set) var automationStatus: PermissionStatus = .notDetermined
    @Published public private(set) var agentNotificationAuthorization: NotificationAuthorization = .notDetermined
    @Published public var agentNotificationError: String?
    /// The module that owns the live notch right now, or nil when the collapsed notch should be bare.
    @Published public private(set) var liveModuleID: String?
    @Published public var settingsTab: SettingsTab = .general
    /// Shown at the top of Settings on the very first launch.
    @Published public var showsWelcome: Bool
    @Published public private(set) var claudeHookStatus: ClaudeHookStatus?
    @Published public var claudeHookError: String?

    /// True when no settings file existed at launch.
    public let isFirstLaunch: Bool

    /// Screen IDs whose panel is open. Modules see one flat "active" flag so a second display keeping its
    /// panel open never stops the first display's monitors.
    private var activePanels: Set<String> = []
    /// The latest activity each module published, keyed by module ID.
    private var liveActivities: [String: LiveActivity] = [:]
    private var liveSubscriptions: [AnyCancellable] = []

    /// Set by the composition root; the UI never calls AppKit or window APIs itself.
    public var openSettings: () -> Void = {}
    public var quit: () -> Void = {}
    public var diagnostics: () -> String = { "" }

    private let store: SettingsPersisting
    private let loginItems: LoginItemControlling
    private let registry: ModuleRegistry
    private let permissions: PermissionRequesting
    private let claudeHook: ClaudeHookInstalling?

    public init(
        store: SettingsPersisting,
        loginItems: LoginItemControlling,
        registry: ModuleRegistry,
        permissions: PermissionRequesting,
        claudeHook: ClaudeHookInstalling? = nil
    ) {
        self.store = store
        self.loginItems = loginItems
        self.registry = registry
        self.permissions = permissions
        self.claudeHook = claudeHook
        self.isFirstLaunch = !store.hasSavedSettings
        self.showsWelcome = !store.hasSavedSettings
        self.claudeHookStatus = claudeHook?.status
        self.settings = store.load()
        // The system login item is the source of truth; a settings file can be stale.
        self.launchAtLogin = loginItems.isEnabled
        syncModules()
        syncPreferredPlayer()
        syncAgentRetention()
        syncAgentNotifications()
        syncLiveActivity()
        refreshAutomationStatus()
        if settings.launchAtLogin != launchAtLogin {
            settings.launchAtLogin = launchAtLogin
            store.save(settings)
        }
        // Write the defaults once so the next launch is not mistaken for the first.
        if isFirstLaunch { store.save(settings) }
        // Publishers emit the new value before the module stores it, so keep what they send.
        liveSubscriptions = registry.allModules.map { module in
            let id = module.id
            return module.liveActivityPublisher.sink { [weak self] activity in
                self?.liveActivities[id] = activity
                self?.recomputeLiveModule()
            }
        }
    }

    // MARK: - Modules

    public var allModules: [any BrimModule] { registry.allModules }

    public func isModuleEnabled(_ id: String) -> Bool {
        settings.enabledModules.contains(id)
    }

    public func showSettings(_ tab: SettingsTab) {
        settingsTab = tab
        openSettings()
    }
    public var disabledModules: [any BrimModule] { registry.disabledModules }

    /// Installed players for the Follow picker. Empty when neither Spotify nor Music is installed.
    public var mediaSources: [NowPlayingSource] {
        registry.allModules
            .compactMap { $0 as? MediaModuleControlling }
            .first?.sources ?? []
    }

    /// The module drawn in the live notch's ears.
    public var liveModule: (any BrimModule)? {
        liveModuleID.flatMap { registry.module(id: $0) }
    }

    /// An open panel on any screen counts as "a panel is open".
    public func setPanelActive(screenID: String, active: Bool) {
        let wasActive = !activePanels.isEmpty
        if active {
            activePanels.insert(screenID)
        } else {
            activePanels.remove(screenID)
        }
        let isActive = !activePanels.isEmpty
        guard wasActive != isActive else { return }
        registry.setPanelActive(isActive)
    }

    private func syncModules() {
        registry.apply(enabledIDs: settings.enabledModules)
        activeModules = registry.enabledModules
        recomputeLiveModule()
    }

    private func syncLiveActivity() {
        for module in registry.allModules {
            (module as? MediaModuleControlling)?.setLiveActivityEnabled(settings.showLiveActivity)
        }
        recomputeLiveModule()
    }

    private func recomputeLiveModule() {
        let next = settings.showLiveActivity
            ? LiveActivityResolver.winner(activeModules.map { ($0.id, liveActivities[$0.id]) })
            : nil
        if next != liveModuleID { liveModuleID = next }
    }

    /// Synchronous so a toggle reflects immediately. A module that needs a permission should go through
    /// the explanation sheet and `enableModuleAfterPermissionExplanation`; this is the fallback.
    public func setModuleEnabled(_ id: String, _ enabled: Bool) {
        guard let module = registry.module(id: id) else { return }
        if enabled, !module.isEnabled, !module.requiredPermissions.isEmpty {
            Task { await enableModuleAfterPermissionExplanation(id) }
            return
        }
        applyModuleEnabled(id, enabled)
    }

    /// Enabling a module is the only place a permission is ever requested. Denial still enables the
    /// module in its degraded form.
    public func enableModuleAfterPermissionExplanation(_ id: String) async {
        guard let module = registry.module(id: id) else { return }
        if !module.isEnabled {
            for kind in module.requiredPermissions where permissions.status(for: kind) != .granted {
                let status = await permissions.request(kind)
                Log.general.info(
                    "Permission \(kind.rawValue, privacy: .public) for module \(id, privacy: .public): \(status.rawValue, privacy: .public)"
                )
            }
        }
        applyModuleEnabled(id, true)
        refreshAutomationStatus()
    }

    private func applyModuleEnabled(_ id: String, _ enabled: Bool) {
        var ids = settings.enabledModules
        if enabled {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        guard ids != settings.enabledModules else { return }
        settings.enabledModules = ids
    }

    /// Swaps an enabled module with its neighbour so the panel order follows the list.
    public func moveModule(id: String, by offset: Int) {
        var ids = settings.enabledModules
        guard let index = ids.firstIndex(of: id) else { return }
        let destination = index + offset
        guard ids.indices.contains(destination) else { return }
        ids.swapAt(index, destination)
        settings.enabledModules = ids
    }

    public func module(id: String) -> (any BrimModule)? {
        registry.module(id: id)
    }

    /// Applies the persisted player choice to whichever module knows how to follow one.
    private func syncPreferredPlayer() {
        for module in registry.allModules {
            (module as? MediaModuleControlling)?.applyPreferredPlayer(settings.preferredPlayerBundleID)
        }
    }

    public func setPreferredPlayer(_ sourceID: String?) {
        let normalized = sourceID?.isEmpty == true ? nil : sourceID
        guard settings.preferredPlayerBundleID != normalized else { return }
        settings.preferredPlayerBundleID = normalized
    }

    /// The panel's source menu cannot show an explanation, so a player that needs Automation takes the user
    /// to Settings → Media, which explains it and has the Grant button. The choice itself is kept.
    public func choosePlayerFromPanel(_ sourceID: String?) {
        setPreferredPlayer(sourceID)
        refreshAutomationStatus()
        if sourceID != nil, automationStatus != .granted {
            showSettings(.media)
        }
    }

    // MARK: - Agents

    /// The agent module is the only owner of the socket and the roster, so settings and diagnostics go
    /// through this narrow surface instead of duplicating its state.
    public var agentModule: (any AgentModuleControlling)? {
        registry.allModules.compactMap { $0 as? AgentModuleControlling }.first
    }

    public var agentSocketPath: String {
        agentModule?.socketPath ?? AgentSocketLocation.defaultPath
    }

    public func clearFinishedAgentSessions() {
        agentModule?.clearFinished()
    }

    public func copyAgentSocketPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(agentSocketPath, forType: .string)
    }

    private func syncAgentRetention() {
        agentModule?.applyRetention(minutes: settings.agentFinishedRetentionMinutes)
    }

    private func syncAgentNotifications() {
        agentModule?.setNotificationsEnabled(settings.agentNotificationsEnabled)
    }

    /// Called only after the in-app explanation. A system denial keeps the notch fallback on.
    public func requestAgentNotificationPermission() async {
        guard let module = agentModule else { return }

        // macOS refuses to present the notification prompt for an accessory-only app. A settings window
        // is already visible, so briefly behaving like a regular app lets the system show its prompt.
        let previousPolicy = NSApp?.activationPolicy() ?? .accessory
        if let app = NSApp, previousPolicy != .regular {
            _ = app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
        }
        defer {
            if let app = NSApp, previousPolicy != .regular {
                _ = app.setActivationPolicy(previousPolicy)
            }
        }

        let status = await module.requestNotificationAuthorization()
        agentNotificationAuthorization = status
        Log.agent.info("Agent notifications permission result: \(status.rawValue, privacy: .public)")

        // The notch alert is the guaranteed path; macOS banners are used when the system allows them.
        if !settings.agentNotificationsEnabled {
            settings.agentNotificationsEnabled = true
        }
        agentNotificationError = status.isAuthorized
            ? nil
            : "macOS banners are unavailable; Brim will show a notch alert."
    }

    /// Reads the system status again; the user can change it in System Settings behind Brim's back.
    public func refreshAgentNotificationAuthorization() async {
        guard let module = agentModule else { return }
        await module.refreshNotificationAuthorization()
        agentNotificationAuthorization = module.notificationAuthorization

        guard settings.agentNotificationsEnabled else { return }
        agentNotificationError = agentNotificationAuthorization.isAuthorized
            ? nil
            : "macOS banners are unavailable; Brim will show a notch alert."
    }

    public func showTestAgentSession() {
        agentModule?.showTestSession()
    }

    // MARK: - Claude Code

    public func refreshClaudeHook() {
        claudeHook?.refresh()
        claudeHookStatus = claudeHook?.status
    }

    public func installClaudeHook() {
        perform { try $0.install() }
    }

    public func removeClaudeHook() {
        perform { try $0.uninstall() }
    }

    private func perform(_ action: (ClaudeHookInstalling) throws -> Void) {
        guard let claudeHook else { return }
        do {
            try action(claudeHook)
            claudeHookError = nil
        } catch {
            claudeHookError = error.localizedDescription
            Log.agent.error("Claude Code hook change failed: \(error.localizedDescription, privacy: .public)")
        }
        claudeHookStatus = claudeHook.status
    }

    public func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Permissions

    public func refreshAutomationStatus() {
        automationStatus = permissions.status(for: .automation)
    }

    /// Only called from a button or after the explanation sheet. Never at launch.
    public func requestAutomationPermission() async {
        let status = await permissions.request(.automation)
        automationStatus = status
        Log.general.info("Automation permission is now \(status.rawValue, privacy: .public)")
    }

    // MARK: - Launch at login

    /// The user can also change this in System Settings, so re-read it whenever settings appears.
    public func refreshLaunchAtLogin() {
        launchAtLogin = loginItems.isEnabled
        if settings.launchAtLogin != launchAtLogin {
            settings.launchAtLogin = launchAtLogin
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItems.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            Log.general.error("Launch at login failed: \(error.localizedDescription)")
        }
        refreshLaunchAtLogin()
    }

    // MARK: - Diagnostics

    public func copyDiagnostics() {
        let report = diagnostics()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
