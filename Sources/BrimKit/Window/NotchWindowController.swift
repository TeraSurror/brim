import AppKit
import QuartzCore
import SwiftUI

/// Owns one screen's window and its pure state machine. The window frame is always exactly the visible
/// panel, so anything outside it falls through to the menu bar or the app below.
///
/// Animation is split in two: the window frame changes over a short ease-out, while the SwiftUI layout
/// fades in once the window is nearly grown. This avoids the content reflowing while its window is still
/// changing size. With Reduce Motion on, the window jumps to its new size and cross-fades instead.
@MainActor
final class NotchWindowController {
    private static let collapseDuration: TimeInterval = 0.24
    private static let expandDuration: TimeInterval = 0.34
    private static let liveDuration: TimeInterval = 0.28
    private static let fadeDuration: TimeInterval = 0.16

    let screenID: String
    let screenFrame: CGRect
    private let window: NotchWindow
    private let geometry: PanelGeometry
    private let panelState: PanelStateModel
    private let machine: PanelStateMachine
    private let scheduler: Scheduling
    private let onActiveChange: (Bool) -> Void

    private var pendingTasks: [TaskHandle] = []
    private var reportedActive = false
    private var isHidden = false
    /// Opened by the shortcut: the window may hold keyboard focus until the panel closes.
    private(set) var isKeyboardOpen = false
    /// Incremented for every visual transition so late callbacks from the previous one do nothing.
    private var generation = 0

    init(
        screen: ScreenInfo,
        model: AppModel,
        metrics: PanelMetrics,
        timings: PanelTimings,
        isLive: Bool,
        isHidden: Bool,
        scheduler: Scheduling,
        onActiveChange: @escaping (Bool) -> Void
    ) {
        let geometry = PanelGeometry(screen: screen, metrics: metrics)
        let panelState = PanelStateModel(showsLiveShape: isLive, showsLiveContent: isLive)
        let machine = PanelStateMachine(
            screen: screen, metrics: metrics, timings: timings, scheduler: scheduler)
        machine.isLive = isLive
        let collapsed = geometry.frame(for: .collapsed, live: isLive)
        let window = NotchWindow(frame: Self.appKitFrame(for: collapsed))

        let root = PanelView(
            model: model,
            panel: panelState,
            isNotched: geometry.isNotched,
            topInset: screen.topInset,
            liveSize: geometry.liveFrame.size,
            earWidth: metrics.liveEarWidth,
            expandedSize: geometry.frame(for: .expanded).size,
            openSettings: { model.openSettings() },
            quit: { model.quit() }
        )
        let hosting = PanelHostingView(rootView: root)
        window.contentView = hosting
        window.setFrame(Self.appKitFrame(for: collapsed), display: false)

        self.screenID = screen.id
        self.screenFrame = screen.frame
        self.window = window
        self.geometry = geometry
        self.panelState = panelState
        self.machine = machine
        self.scheduler = scheduler
        self.onActiveChange = onActiveChange

        applyCollapsedWindowState()

        machine.onStateChange = { [weak self] state in
            self?.transition(to: state)
        }
        window.onCancel = { [weak self] in self?.closeFromKeyboard() }
        window.onResignKey = { [weak self] in
            // Clicking another app or the desktop takes focus away; that closes a keyboard-opened panel.
            guard let self, self.isKeyboardOpen else { return }
            self.closeFromKeyboard()
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
            let state = self.machine.state
            let slop = state == .expanded ? self.machine.timings.exitSlop : 1
            guard !self.geometry.contains(point, in: state, live: self.machine.isLive, slop: slop) else { return }
            self.machine.pointerMoved(to: point)
        }
        setHidden(isHidden)

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

    /// Takes the panel off screen while another app is full screen here, so a video or game is never
    /// covered. The state machine is disabled, which also collapses an open panel.
    func setHidden(_ hidden: Bool) {
        isHidden = hidden
        // A panel the user explicitly opened stays until it is closed; it hides on the way out.
        guard !isKeyboardOpen else { return }
        machine.isEnabled = !hidden
        if hidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    /// The shortcut is an explicit request, so it also opens over a full-screen app on this display.
    func openFromKeyboard() {
        isKeyboardOpen = true
        machine.isEnabled = true
        window.acceptsKeyboardFocus = true
        machine.expandFromKeyboard()
        // Non-activating: the window takes key focus while the front app stays active.
        window.makeKeyAndOrderFront(nil)
    }

    func closeFromKeyboard() {
        machine.collapseNow()
    }

    /// Gives keyboard focus back. Ordering the key window out makes the window server return focus to the
    /// active app, which never stopped being active.
    private func endKeyboardFocus() {
        guard isKeyboardOpen else { return }
        isKeyboardOpen = false
        window.acceptsKeyboardFocus = false
        if window.isKeyWindow {
            window.orderOut(nil)
            if !isHidden { window.orderFrontRegardless() }
        }
        if isHidden {
            machine.isEnabled = false
        }
    }

    /// Grows the collapsed notch into its ears, or retracts them. An open panel just remembers the value and
    /// collapses to the right frame later.
    func setLive(_ live: Bool) {
        guard live != machine.isLive else { return }
        machine.isLive = live
        guard machine.state == .collapsed else { return }
        if panelState.state != .collapsed {
            // Still retracting from the open panel: restart the collapse toward the new frame so its
            // finishing step (and the inactive report) is not lost.
            transition(to: .collapsed)
            return
        }

        generation += 1
        let generation = self.generation
        cancelPendingTasks()

        if live {
            panelState.showsLiveShape = true
            panelState.showsLiveContent = true
            applyCollapsedWindowState()
            animateFrame(to: geometry.liveFrame, duration: Self.liveDuration)
        } else {
            // Fade the ear content, then let the black shape shrink back into the hardware notch.
            panelState.showsLiveContent = false
            animateFrame(to: geometry.collapsedFrame, duration: Self.liveDuration)
            schedule(after: Self.liveDuration, generation: generation) { [weak self] in
                guard let self, self.machine.state == .collapsed, !self.machine.isLive else { return }
                self.panelState.showsLiveShape = false
                self.applyCollapsedWindowState()
            }
        }
    }

    func close() {
        cancelPendingTasks()
        reportActive(false)
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Visual transitions

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func transition(to state: PanelState) {
        generation += 1
        let generation = self.generation
        cancelPendingTasks()

        switch state {
        case .collapsed:
            collapse(generation: generation)
        case .expanded:
            expand(generation: generation)
        }
    }

    /// Visible and clickable whenever something is drawn: the handle on a plain screen or the live ears.
    /// The bare notch is invisible and lets clicks through, because the menu bar sits right beside it.
    private func applyCollapsedWindowState() {
        let visible = !geometry.isNotched || machine.isLive
        window.alphaValue = visible ? 1 : 0
        window.ignoresMouseEvents = !visible
    }

    private func collapse(generation: Int) {
        let target = geometry.frame(for: .collapsed, live: machine.isLive)
        panelState.content = .collapsed
        window.ignoresMouseEvents = true
        let wasHidden = isHidden && isKeyboardOpen
        endKeyboardFocus()

        let finish: () -> Void = { [weak self] in
            guard let self, self.machine.state == .collapsed else { return }
            self.panelState.state = .collapsed
            self.panelState.showsLiveShape = self.machine.isLive
            self.panelState.showsLiveContent = self.machine.isLive
            self.applyCollapsedWindowState()
            if wasHidden, self.isHidden { self.window.orderOut(nil) }
            // The panel is no longer visible; modules can stop their monitors now.
            self.reportActive(false)
        }

        if reduceMotion {
            fade(to: 0) { [weak self] in
                guard let self, self.generation == generation else { return }
                self.window.setFrame(Self.appKitFrame(for: target), display: true)
                finish()
            }
            return
        }

        // Keep `panelState.state` expanded while the window retracts, so the black shape is visible
        // shrinking into the notch rather than blinking out before the window moves.
        animateFrame(to: target, duration: Self.collapseDuration)
        schedule(after: Self.collapseDuration, generation: generation, finish)
    }

    private func expand(generation: Int) {
        panelState.state = .expanded
        reportActive(true)
        window.ignoresMouseEvents = false
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        let target = geometry.frame(for: .expanded)
        if reduceMotion {
            window.alphaValue = 0
            window.setFrame(Self.appKitFrame(for: target), display: true)
            panelState.content = .expanded
            fade(to: 1)
            return
        }

        window.alphaValue = 1
        animateFrame(to: target, duration: Self.expandDuration)
        if panelState.content != .expanded {
            schedule(after: 0.2, generation: generation) { [weak self] in
                guard let self, self.machine.state == .expanded else { return }
                self.panelState.content = .expanded
            }
        }
    }

    /// Collapses duplicate reports. The panel is active from the moment it starts opening until the collapse
    /// animation has finished, so modules never tear down content that is still on screen.
    private func reportActive(_ active: Bool) {
        guard active != reportedActive else { return }
        reportedActive = active
        onActiveChange(active)
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

    private func fade(to alpha: CGFloat, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            window.animator().alphaValue = alpha
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
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
