import CoreGraphics
import Foundation

/// Pure hover/expand logic for one display. No AppKit, no polling: the window layer forwards pointer events,
/// and all delays run through the injected `Scheduling` so tests can drive a fake clock.
@MainActor
public final class PanelStateMachine {
    public private(set) var state: PanelState
    public var timings: PanelTimings
    public var onStateChange: ((PanelState) -> Void)?

    public var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { collapseNow() }
        }
    }

    /// True while the collapsed notch is widened by live content. The ears are part of the hover target.
    /// Changing it never opens the panel by itself: ears appearing under a resting pointer are not a hover.
    public var isLive: Bool = false

    /// True while a panel opened from the keyboard is open. The pointer leaving does not collapse it; Esc,
    /// the shortcut again or a click outside do.
    public private(set) var isHeldOpen = false

    private let scheduler: Scheduling
    private let geometry: PanelGeometry
    private var lastPoint: CGPoint?
    private var openTask: TaskHandle?
    private var collapseTask: TaskHandle?

    public init(
        screen: ScreenInfo,
        metrics: PanelMetrics = PanelMetrics(),
        timings: PanelTimings = PanelTimings(),
        scheduler: Scheduling,
        state: PanelState = .collapsed
    ) {
        self.geometry = PanelGeometry(screen: screen, metrics: metrics)
        self.timings = timings
        self.scheduler = scheduler
        self.state = state
    }

    /// Call for every pointer move, on every display. Moves outside this display are how it learns to collapse.
    public func pointerMoved(to point: CGPoint) {
        lastPoint = point
        guard isEnabled else { return }

        switch state {
        case .collapsed:
            if timings.opensOnHover, isOverCollapsed(point) {
                scheduleOpen()
            } else {
                cancelOpen()
            }
        case .expanded:
            if isHeldOpen || geometry.contains(point, in: .expanded, slop: timings.exitSlop) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
        }
    }

    /// A click on the notch opens the panel immediately, in both hover and click-only mode. A click outside
    /// a panel held open by the keyboard closes it.
    public func clicked(at point: CGPoint) {
        guard isEnabled else { return }
        lastPoint = point
        if state == .collapsed, isOverCollapsed(point) {
            expandNow()
        } else if isHeldOpen, !geometry.contains(point, in: .expanded, slop: timings.exitSlop) {
            collapseNow()
        }
    }

    /// Scrolling down over the notch opens the panel at once, in hover and click mode alike. Scrolling up
    /// over the open panel's top strip closes it.
    public func scrolled(_ gesture: ScrollGesture, at point: CGPoint) {
        guard isEnabled else { return }
        lastPoint = point
        switch (state, gesture) {
        case (.collapsed, .down) where isOverCollapsed(point):
            expandNow()
        case (.expanded, .up) where geometry.expandedTopStrip.insetBy(dx: 0, dy: -1).contains(point):
            collapseNow()
        default:
            break
        }
    }

    /// True when a horizontal swipe here should reach the live module: the ears are showing and the panel
    /// is closed.
    public func acceptsSwipe(at point: CGPoint) -> Bool {
        isEnabled && state == .collapsed && isLive && isOverCollapsed(point)
    }

    /// Opens at once and stays open until it is closed on purpose. Opening a panel that hover already
    /// opened just holds it.
    public func expandFromKeyboard() {
        isHeldOpen = true
        expandNow()
    }

    /// Used by the window layer when a screen goes away or the app updates its geometry.
    public func collapseNow() {
        cancelOpen()
        cancelCollapse()
        transition(to: .collapsed)
    }

    public func update(timings: PanelTimings) {
        self.timings = timings
        if !timings.opensOnHover { cancelOpen() }
    }

    private func isOverCollapsed(_ point: CGPoint) -> Bool {
        geometry.contains(point, in: .collapsed, live: isLive, slop: 1)
    }

    // MARK: - Timers

    private func scheduleOpen() {
        guard openTask == nil else { return }
        openTask = scheduler.schedule(after: timings.hoverDelay) { [weak self] in
            self?.openFired()
        }
    }

    private func openFired() {
        openTask = nil
        guard isEnabled, timings.opensOnHover, let point = lastPoint, isOverCollapsed(point) else { return }
        expandNow()
    }

    private func expandNow() {
        cancelOpen()
        cancelCollapse()
        guard state != .expanded else { return }
        Log.state.debug("expanded")
        transition(to: .expanded)
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        collapseTask = scheduler.schedule(after: timings.collapseDelay) { [weak self] in
            self?.collapseFired()
        }
    }

    private func collapseFired() {
        collapseTask = nil
        guard isEnabled, !isHeldOpen else { return }
        // A late move back into the panel cancels the timer, but double-check the last known point in case
        // the pointer left and no move event arrived at the boundary.
        if let point = lastPoint, state == .expanded,
           geometry.contains(point, in: .expanded, slop: timings.exitSlop) {
            return
        }
        Log.state.debug("collapsed")
        transition(to: .collapsed)
    }

    private func cancelOpen() {
        openTask?.cancel()
        openTask = nil
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func transition(to newState: PanelState) {
        if newState == .collapsed { isHeldOpen = false }
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }
}
