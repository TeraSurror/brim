import AppKit
import QuartzCore
import SwiftUI

/// Owns one screen's window and its pure state machine. The window frame is always exactly the visible
/// panel, so anything outside it falls through to the menu bar or the app below.
///
/// Animation is split in two: the window frame changes over a short ease-out, while the SwiftUI layout
/// changes are sequenced (peek first, expanded content once the window is nearly grown). This avoids the
/// content reflowing while its window is still changing size.
@MainActor
final class NotchWindowController {
    private static let collapseDuration: TimeInterval = 0.24
    private static let peekDuration: TimeInterval = 0.24
    private static let expandDuration: TimeInterval = 0.36

    let screenID: String
    private let window: NotchWindow
    private let geometry: PanelGeometry
    private let panelState: PanelStateModel
    private let machine: PanelStateMachine
    private let scheduler: Scheduling

    private var pendingTasks: [TaskHandle] = []
    /// Incremented for every visual transition so late callbacks from the previous one do nothing.
    private var generation = 0

    init(
        screen: ScreenInfo,
        model: AppModel,
        metrics: PanelMetrics,
        timings: PanelTimings,
        scheduler: Scheduling
    ) {
        let geometry = PanelGeometry(screen: screen, metrics: metrics)
        let panelState = PanelStateModel()
        let machine = PanelStateMachine(
            screen: screen, metrics: metrics, timings: timings, scheduler: scheduler)
        let collapsed = geometry.frame(for: .collapsed)
        let window = NotchWindow(frame: Self.appKitFrame(for: collapsed))

        let root = PanelView(
            model: model,
            panel: panelState,
            isNotched: geometry.isNotched,
            topInset: screen.topInset,
            peekSize: geometry.frame(for: .peek).size,
            expandedSize: geometry.frame(for: .expanded).size,
            openSettings: { model.openSettings() },
            quit: { model.quit() }
        )
        let hosting = PanelHostingView(rootView: root)
        window.contentView = hosting
        window.setFrame(Self.appKitFrame(for: collapsed), display: false)

        self.screenID = screen.id
        self.window = window
        self.geometry = geometry
        self.panelState = panelState
        self.machine = machine
        self.scheduler = scheduler

        // A notched screen's collapsed window is invisible and sits right over the notch; letting it take
        // mouse events would steal clicks from the menu bar. The global pointer monitor still sees hovers.
        // Alpha 0 also guarantees no stray shadow or background pixel can show around the notch.
        window.ignoresMouseEvents = geometry.isNotched
        window.alphaValue = geometry.isNotched ? 0 : 1

        machine.onStateChange = { [weak self] state in
            self?.transition(to: state)
        }
        hosting.onMouseEntered = { [weak self] in
            guard let self else { return }
            self.machine.pointerMoved(to: Self.cgPoint(from: NSEvent.mouseLocation))
        }
        hosting.onMouseExited = { [weak self] in
            guard let self else { return }
            let point = Self.cgPoint(from: NSEvent.mouseLocation)
            // Resizing the window under a still pointer can look like an exit to a tracking area.
            // Only forward a real exit.
            let slop = self.panelState.state == .expanded ? self.machine.timings.exitSlop : 1
            guard !self.geometry.contains(point, in: self.panelState.state, slop: slop) else { return }
            self.machine.pointerMoved(to: point)
        }
        window.orderFrontRegardless()

        Log.window.info("Panel for \(screen.id, privacy: .public): notch \(geometry.isNotched, privacy: .public), collapsed \(Int(collapsed.width), privacy: .public)×\(Int(collapsed.height), privacy: .public) at (\(Int(collapsed.minX), privacy: .public), \(Int(collapsed.minY), privacy: .public))")
    }

    func pointerMoved(to point: CGPoint) {
        machine.pointerMoved(to: point)
    }

    func clicked(at point: CGPoint) {
        machine.clicked(at: point)
    }

    func update(timings: PanelTimings) {
        machine.update(timings: timings)
    }

    func close() {
        cancelPendingTasks()
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Visual transitions

    private func transition(to state: PanelState) {
        generation += 1
        let generation = self.generation
        cancelPendingTasks()

        switch state {
        case .collapsed:
            collapse(generation: generation)
        case .peek:
            peek(generation: generation)
        case .expanded:
            expand(generation: generation)
        }
    }

    private func collapse(generation: Int) {
        panelState.content = .collapsed
        // Keep `panelState.state` at peek/expanded while the window retracts, so the black shape is visible
        // shrinking into the notch rather than blinking out before the window moves.
        window.ignoresMouseEvents = true
        animateFrame(to: geometry.frame(for: .collapsed), duration: Self.collapseDuration)

        schedule(after: Self.collapseDuration, generation: generation) { [weak self] in
            guard let self, self.machine.state == .collapsed else { return }
            self.panelState.state = .collapsed
            self.window.alphaValue = self.geometry.isNotched ? 0 : 1
            self.window.ignoresMouseEvents = self.geometry.isNotched
        }
    }

    private func peek(generation: Int) {
        panelState.state = .peek
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        animateFrame(to: geometry.frame(for: .peek), duration: Self.peekDuration)

        if panelState.content == .expanded {
            panelState.content = .peek
        } else if panelState.content == .collapsed {
            // Let the strip grow a little before the compact content fades in.
            schedule(after: 0.07, generation: generation) { [weak self] in
                guard let self, self.machine.state == .peek else { return }
                self.panelState.content = .peek
            }
        }
    }

    private func expand(generation: Int) {
        panelState.state = .expanded
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        animateFrame(to: geometry.frame(for: .expanded), duration: Self.expandDuration)

        if panelState.content == .collapsed {
            // A click can jump straight from the notch to the full panel. Show the compact content while
            // the window grows, then hand over to the expanded layout near the end.
            schedule(after: 0.07, generation: generation) { [weak self] in
                guard let self, self.machine.state == .expanded else { return }
                self.panelState.content = .peek
            }
        }
        if panelState.content != .expanded {
            schedule(after: 0.26, generation: generation) { [weak self] in
                guard let self, self.machine.state == .expanded else { return }
                self.panelState.content = .expanded
            }
        }
    }

    // MARK: - Timing

    private func schedule(
        after delay: TimeInterval,
        generation: Int,
        _ action: @escaping @MainActor () -> Void
    ) {
        let task = scheduler.schedule(after: delay) { [weak self] in
            guard let self, self.generation == generation else { return }
            action()
        }
        pendingTasks.append(task)
    }

    private func cancelPendingTasks() {
        for task in pendingTasks { task.cancel() }
        pendingTasks.removeAll()
    }

    // MARK: - Window frame

    private func animateFrame(to cgFrame: CGRect, duration: TimeInterval) {
        let target = Self.appKitFrame(for: cgFrame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            // Ease-out rather than overshoot: the panel grows out of the notch without bouncing past it.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.92, 0.24, 1.0)
            window.animator().setFrame(target, display: true)
        }
        Log.window.debug(
            "Frame \(Int(cgFrame.width), privacy: .public)×\(Int(cgFrame.height), privacy: .public) on \(self.screenID, privacy: .public)"
        )
    }

    /// Converts a CoreGraphics global rect (top-left origin) to AppKit's bottom-left primary screen space.
    private static func appKitFrame(for cgFrame: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: cgFrame.minX,
            y: primaryHeight - cgFrame.maxY,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }

    private static func cgPoint(from point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
