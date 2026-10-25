import AppKit
import Combine

/// Composition root: builds the real services and wires them to the panel and settings windows.
@MainActor
public final class AppController {
    let model: AppModel

    private let screens: ScreenProviding
    private let scheduler: Scheduling
    private let monitor: PointerMonitoring
    private let windows = WindowPresenter()
    private var windowManager: NotchWindowManager?
    private var cancellables = Set<AnyCancellable>()

    public init() {
        let registry = ModuleRegistry(modules: [ClockModule()])
        self.screens = NSScreenProvider()
        self.scheduler = DispatchScheduler()
        self.monitor = NSEventPointerMonitor()
        self.model = AppModel(
            store: JSONSettingsStore(),
            loginItems: SMLoginItemService(),
            registry: registry,
            permissions: SystemPermissionService()
        )
    }

    public func start() {
        guard windowManager == nil else { return }

        model.openSettings = { [weak self] in self?.openSettings() }
        model.quit = { NSApp.terminate(nil) }
        model.diagnostics = { [weak self] in
            guard let self else { return "" }
            return Diagnostics.report(settings: self.model.settings, screens: self.screens)
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

        Log.general.info("Brim started with \(self.model.activeModules.count, privacy: .public) active module(s)")
    }

    public func openSettings() {
        windows.showSettings(model: model)
    }
}
