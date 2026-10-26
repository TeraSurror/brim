import AppKit
import Combine
import Foundation

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
        }
    }

    @Published public private(set) var launchAtLogin: Bool
    @Published public var launchAtLoginError: String?
    @Published public private(set) var activeModules: [any BrimModule] = []
    @Published public private(set) var automationStatus: PermissionStatus = .notDetermined

    /// Screen IDs whose panel is peek or expanded. Modules see one flat "active" flag so a second display
    /// keeping its panel open never stops the first display's monitors.
    private var activePanels: Set<String> = []

    /// Set by the composition root; the UI never calls AppKit or window APIs itself.
    public var openSettings: () -> Void = {}
    public var quit: () -> Void = {}
    public var diagnostics: () -> String = { "" }

    private let store: SettingsPersisting
    private let loginItems: LoginItemControlling
    private let registry: ModuleRegistry
    private let permissions: PermissionRequesting

    public init(
        store: SettingsPersisting,
        loginItems: LoginItemControlling,
        registry: ModuleRegistry,
        permissions: PermissionRequesting
    ) {
        self.store = store
        self.loginItems = loginItems
        self.registry = registry
        self.permissions = permissions
        self.settings = store.load()
        // The system login item is the source of truth; a settings file can be stale.
        self.launchAtLogin = loginItems.isEnabled
        syncModules()
        syncPreferredPlayer()
        syncAgentRetention()
        refreshAutomationStatus()
        if settings.launchAtLogin != launchAtLogin {
            settings.launchAtLogin = launchAtLogin
            store.save(settings)
        }
    }

    // MARK: - Modules

    public var allModules: [any BrimModule] { registry.allModules }
    public var disabledModules: [any BrimModule] { registry.disabledModules }

    /// Installed players for the Follow picker. Empty when neither Spotify nor Music is installed.
    public var mediaSources: [NowPlayingSource] {
        registry.allModules
            .compactMap { $0 as? MediaModuleControlling }
            .first?.sources ?? []
    }

    /// Peek and expanded both count as "a panel is open"; the media module starts its helper here.
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
