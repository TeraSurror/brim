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

    private let scheduler: Scheduling
    private let geometry: PanelGeometry
    private var lastPoint: CGPoint?
    private var peekTask: TaskHandle?
    private var expandTask: TaskHandle?
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
            if geometry.contains(point, in: .collapsed, slop: 1) {
                schedulePeek()
            } else {
                cancelPeek()
            }
        case .peek:
            if geometry.contains(point, in: .peek) {
                cancelCollapse()
                scheduleExpansion()
            } else {
                cancelExpansion()
                scheduleCollapse()
            }
        case .expanded:
            if geometry.contains(point, in: .expanded, slop: timings.exitSlop) {
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
        }
    }

    /// A click on the notch or peek opens the full panel immediately; the spec gives clicking priority over
    /// waiting for the longer hover.
    public func clicked(at point: CGPoint) {
        guard isEnabled else { return }
        lastPoint = point
        switch state {
        case .collapsed where geometry.contains(point, in: .collapsed, slop: 1):
            expandNow()
        case .peek where geometry.contains(point, in: .peek):
            expandNow()
        case .expanded:
            break
        default:
            break
        }
    }

    /// Used by the window layer when a screen goes away or the app updates its geometry.
    public func collapseNow() {
        cancelPeek()
        cancelExpansion()
        cancelCollapse()
        transition(to: .collapsed)
    }

    public func update(timings: PanelTimings) {
        self.timings = timings
    }

    // MARK: - Timers

    private func schedulePeek() {
        guard peekTask == nil else { return }
        peekTask = scheduler.schedule(after: timings.hoverDelay) { [weak self] in
            self?.peekFired()
        }
    }

    private func peekFired() {
        peekTask = nil
        guard isEnabled, let point = lastPoint, geometry.contains(point, in: .collapsed, slop: 1) else { return }
        Log.state.debug("peek")
        transition(to: .peek)
        scheduleExpansion()
    }

    private func scheduleExpansion() {
        guard expandTask == nil else { return }
        expandTask = scheduler.schedule(after: timings.expandDelay) { [weak self] in
            self?.expandFired()
        }
    }

    private func expandFired() {
        expandTask = nil
        guard isEnabled, let point = lastPoint, geometry.contains(point, in: .peek) else { return }
        expandNow()
    }

    private func expandNow() {
        cancelPeek()
        cancelExpansion()
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
        guard isEnabled else { return }
        // A late move back into the panel cancels the timer, but double-check the last known point in case
        // the pointer left and no move event arrived at the boundary.
        if let point = lastPoint {
            switch state {
            case .peek where geometry.contains(point, in: .peek):
                return
            case .expanded where geometry.contains(point, in: .expanded, slop: timings.exitSlop):
                return
            default:
                break
            }
        }
        Log.state.debug("collapsed")
        transition(to: .collapsed)
    }

    private func cancelPeek() {
        peekTask?.cancel()
        peekTask = nil
    }

    private func cancelExpansion() {
        expandTask?.cancel()
        expandTask = nil
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func transition(to newState: PanelState) {
        guard state != newState else { return }
        state = newState
        onStateChange?(newState)
    }
}
