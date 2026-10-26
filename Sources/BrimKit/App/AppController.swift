import AppKit
import Combine

/// Composition root: builds the real services and wires them to the panel and settings windows.
@MainActor
public final class AppController {
    let model: AppModel

    private let screens: ScreenProviding
    private let scheduler: Scheduling
    private let monitor: PointerMonitoring
    private let coordinator: NowPlayingCoordinator
    private let agent: AgentModule
    private let windows = WindowPresenter()
    private var windowManager: NotchWindowManager?
    private var cancellables = Set<AnyCancellable>()

    public init() {
        let scheduler = DispatchScheduler()
        let discovery = InstalledPlayerDiscovery()
        let coordinator = NowPlayingCoordinator(
            adapter: MediaAdapterService(),
            automation: AppleEventsPlayerAutomation(discovery: discovery),
            discovery: discovery,
            scheduler: scheduler
        )
        let media = MediaModule(service: coordinator, scheduler: scheduler)
        let screens = NSScreenProvider()
        let agent = AgentModule(alertPresenter: AgentAlertPresenter(screens: screens, scheduler: scheduler))
        let model = AppModel(
            store: JSONSettingsStore(),
            loginItems: SMLoginItemService(),
            registry: ModuleRegistry(modules: [ClockModule(), media, agent]),
            permissions: SystemPermissionService()
        )
        // The panel's source menu writes through settings so the choice survives a restart.
        media.onPreferredPlayerChange = { [weak model] sourceID in
            model?.setPreferredPlayer(sourceID)
        }

        self.model = model
        self.coordinator = coordinator
        self.agent = agent
        self.screens = screens
        self.scheduler = scheduler
        self.monitor = NSEventPointerMonitor()
    }

    public func start() {
        guard windowManager == nil else { return }

        model.openSettings = { [weak self] in self?.openSettings() }
        model.quit = { NSApp.terminate(nil) }
        model.diagnostics = { [weak self] in
            guard let self else { return "" }
            let track = self.coordinator.current.map {
                "\($0.title) — \($0.source.name) (\($0.isPlaying ? "playing" : "paused"))"
            }
            return Diagnostics.report(
                settings: self.model.settings,
                screens: self.screens,
                media: MediaDiagnostics(
                    helperBundled: MediaAdapterLocation.bundled() != nil,
                    helperAvailable: self.coordinator.isAvailable,
                    followedPlayer: self.model.settings.preferredPlayerBundleID,
                    track: track
                ),
                agents: AgentDiagnostics(
                    socketPath: self.agent.socketPath,
                    listening: self.agent.isListening,
                    summary: self.agent.summary,
                    notificationsEnabled: self.agent.notificationsEnabled,
                    notificationAuthorization: self.agent.notificationAuthorization
                )
            )
        }

        let manager = NotchWindowManager(
            model: model,
            screens: screens,
            scheduler: scheduler,
            monitor: monitor
        )
        windowManager = manager
        manager.apply(model.settings)

        model.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.windowManager?.apply(settings) }
            .store(in: &cancellables)

        Task { [weak self] in
            await self?.model.refreshAgentNotificationAuthorization()
        }

        Log.general.info("Brim started with \(self.model.activeModules.count, privacy: .public) active module(s)")
    }

    public func openSettings() {
        windows.showSettings(model: model)
    }

    /// `brim://agent` URLs arrive from the app delegate. The router accepts only the documented fields, so
    /// a link from another app cannot inject malformed state.
    public func handle(_ url: URL) {
        guard let command = AgentURLRouter.command(from: url) else {
            Log.agent.error("Ignored an agent URL: \(url.absoluteString, privacy: .public)")
            return
        }
        agent.handle(command)
    }

    /// Cleans up the agent socket on quit; the listener is otherwise stopped when the module is disabled.
    public func stop() {
        agent.setEnabled(false)
    }
}
