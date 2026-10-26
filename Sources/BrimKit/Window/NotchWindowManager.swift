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
    private let fullScreen: FullScreenDetecting
    private var metrics: PanelMetrics
    private var controllers: [String: NotchWindowController] = [:]
    /// Screen IDs in display order, so the keyboard falls back to the first display that shows Brim.
    private var controllerOrder: [String] = []
    private var screenObserver: NSObjectProtocol?
    private var rebuildTask: TaskHandle?
    private var displayMode: DisplayMode
    private var moduleCount: Int
    private var isLive: Bool
    private var screenSignature = ""
    private var cancellables = Set<AnyCancellable>()

    init(
        model: AppModel,
        screens: ScreenProviding = NSScreenProvider(),
        scheduler: Scheduling = DispatchScheduler(),
        monitor: PointerMonitoring,
        fullScreen: FullScreenDetecting
    ) {
        self.model = model
        self.screens = screens
        self.scheduler = scheduler
        self.monitor = monitor
        self.fullScreen = fullScreen
        self.moduleCount = model.activeModules.count
        self.metrics = PanelMetrics(moduleCount: model.activeModules.count)
        self.isLive = model.liveModuleID != nil
        self.displayMode = model.settings.displayMode

        monitor.onMove = { [weak self] point in self?.pointerMoved(to: point) }
        monitor.onLeftClick = { [weak self] point in self?.clicked(at: point) }
        monitor.start()

        fullScreen.onChange = { [weak self] covered in self?.setFullScreen(covered) }
        fullScreen.start()

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

    /// Called whenever settings change. Timing changes apply live; a new display mode needs new windows.
    func apply(_ settings: Settings) {
        let timings = Self.timings(for: settings)
        for controller in controllers.values {
            controller.update(timings: timings)
        }
        if settings.displayMode != displayMode {
            displayMode = settings.displayMode
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

    /// The open-panel shortcut: closes a keyboard-opened panel, otherwise opens the panel under the pointer.
    func toggleFromKeyboard() {
        if let open = controllers.values.first(where: \.isKeyboardOpen) {
            open.closeFromKeyboard()
            return
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let mouse = NSEvent.mouseLocation
        let pointer = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        let ordered = controllerOrder.compactMap { controllers[$0] }
        let target = ordered.first { $0.screenFrame.contains(pointer) } ?? ordered.first
        target?.openFromKeyboard()
    }

    private func setFullScreen(_ covered: Set<String>) {
        for controller in controllers.values {
            controller.setHidden(covered.contains(controller.screenID))
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
        fullScreen.stop()
        fullScreen.onChange = nil
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
        let eligibleScreens = settings.displayMode.screens(in: currentScreens)
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
                isHidden: fullScreen.coveredScreenIDs.contains(screen.id),
                scheduler: scheduler,
                onActiveChange: { [weak model] active in
                    model?.setPanelActive(screenID: screen.id, active: active)
                }
            )
        }

        controllers = next
        controllerOrder = eligibleScreens.map(\.id)
        for controller in previous.values where next[controller.screenID] !== controller {
            controller.close()
        }
        Log.window.info("Built \(next.count, privacy: .public) panel window(s) for \(currentScreens.count, privacy: .public) screen(s)")
    }

    private static func signature(for screens: [ScreenInfo]) -> String {
        screens.map {
            "\($0.id)|\($0.frame.origin.x),\($0.frame.origin.y),\($0.frame.width),\($0.frame.height)"
                + "|\($0.topInset)|\($0.menuBarHeight)|\($0.auxiliaryLeftWidth ?? -1)|\($0.auxiliaryRightWidth ?? -1)"
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
