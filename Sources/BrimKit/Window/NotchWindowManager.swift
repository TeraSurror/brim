import AppKit
import Combine
import CoreGraphics
import Foundation

/// Keeps exactly one panel window per eligible screen and forwards pointer events and the live notch state
/// to each screen's controller. Rebuilds on display changes so plugging in a monitor never leaves a stray
/// window, and when the module count changes because the expanded width depends on it.
@MainActor
final class NotchWindowManager {
    private let model: AppModel
    private let screens: ScreenProviding
    private let scheduler: Scheduling
    private let monitor: PointerMonitoring
    private var metrics: PanelMetrics
    private var controllers: [String: NotchWindowController] = [:]
    private var screenObserver: NSObjectProtocol?
    private var rebuildTask: TaskHandle?
    private var showOnNonNotchedDisplays: Bool
    private var moduleCount: Int
    private var isLive: Bool
    private var screenSignature = ""
    private var cancellables = Set<AnyCancellable>()

    init(
        model: AppModel,
        screens: ScreenProviding = NSScreenProvider(),
        scheduler: Scheduling = DispatchScheduler(),
        monitor: PointerMonitoring
    ) {
        self.model = model
        self.screens = screens
        self.scheduler = scheduler
        self.monitor = monitor
        self.moduleCount = model.activeModules.count
        self.metrics = PanelMetrics(moduleCount: model.activeModules.count)
        self.isLive = model.liveModuleID != nil
        self.showOnNonNotchedDisplays = model.settings.showOnNonNotchedDisplays

        monitor.onMove = { [weak self] point in self?.pointerMoved(to: point) }
        monitor.onLeftClick = { [weak self] point in self?.clicked(at: point) }
        monitor.start()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }

        // `@Published` emits before the property is stored, so both sinks use the emitted value.
        model.$liveModuleID
            .map { $0 != nil }
            .removeDuplicates()
            .sink { [weak self] live in self?.setLive(live) }
            .store(in: &cancellables)
        model.$activeModules
            .map(\.count)
            .removeDuplicates()
            .sink { [weak self] count in self?.setModuleCount(count) }
            .store(in: &cancellables)

        rebuild()
    }

    /// Called whenever settings change. Timing changes apply live; the non-notched toggle needs new windows.
    func apply(_ settings: Settings) {
        let timings = Self.timings(for: settings)
        for controller in controllers.values {
            controller.update(timings: timings)
        }
        if settings.showOnNonNotchedDisplays != showOnNonNotchedDisplays {
            showOnNonNotchedDisplays = settings.showOnNonNotchedDisplays
            // `@Published` fires before the property is stored, so pass this value explicitly.
            rebuild(force: true, using: settings)
        }
    }

    private func setLive(_ live: Bool) {
        guard live != isLive else { return }
        isLive = live
        for controller in controllers.values {
            controller.setLive(live)
        }
    }

    private func setModuleCount(_ count: Int) {
        guard count != moduleCount else { return }
        moduleCount = count
        metrics = PanelMetrics(moduleCount: count)
        rebuild(force: true)
    }

    func stop() {
        cancellables.removeAll()
        rebuildTask?.cancel()
        rebuildTask = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        monitor.stop()
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
    }

    // MARK: - Pointer

    private func pointerMoved(to point: CGPoint) {
        // Every display sees every move; a point outside a panel is how that panel learns to collapse.
        for controller in controllers.values {
            controller.pointerMoved(to: point)
        }
    }

    private func clicked(at point: CGPoint) {
        for controller in controllers.values {
            controller.clicked(at: point)
        }
    }

    // MARK: - Screens

    private func scheduleRebuild() {
        rebuildTask?.cancel()
        rebuildTask = scheduler.schedule(after: 0.25) { [weak self] in
            self?.rebuildTask = nil
            self?.rebuild(force: false)
        }
    }

    private func rebuild(force: Bool = false, using explicitSettings: Settings? = nil) {
        let settings = explicitSettings ?? model.settings
        let timings = Self.timings(for: settings)
        let currentScreens = screens.screens
        // macOS sends several screen-parameter notifications during launch. Rebuilding on each one
        // would throw away a panel the user is already hovering.
        let eligibleScreens = currentScreens.filter { $0.hasNotch || settings.showOnNonNotchedDisplays }
        let signature = Self.signature(for: eligibleScreens)
        guard force || signature != screenSignature else {
            for controller in controllers.values {
                controller.update(timings: timings)
            }
            return
        }
        screenSignature = signature

        let previous = controllers
        var next: [String: NotchWindowController] = [:]

        for screen in eligibleScreens {
            next[screen.id] = NotchWindowController(
                screen: screen,
                model: model,
                metrics: metrics,
                timings: timings,
                isLive: isLive,
                scheduler: scheduler,
                onActiveChange: { [weak model] active in
                    model?.setPanelActive(screenID: screen.id, active: active)
                }
            )
        }

        controllers = next
        for controller in previous.values where next[controller.screenID] !== controller {
            controller.close()
        }
        Log.window.info("Built \(next.count, privacy: .public) panel window(s) for \(currentScreens.count, privacy: .public) screen(s)")
    }

    private static func signature(for screens: [ScreenInfo]) -> String {
        screens.map {
            "\($0.id)|\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width),\($0.frame.height)"
                + "|\($0.topInset)|\($0.auxiliaryLeftWidth ?? -1)|\($0.auxiliaryRightWidth ?? -1)"
        }.joined(separator: ";")
    }

    private static func timings(for settings: Settings) -> PanelTimings {
        PanelTimings(
            hoverDelay: settings.hoverDelay,
            collapseDelay: settings.collapseDelay,
            opensOnHover: settings.opensOnHover
        )
    }
}
