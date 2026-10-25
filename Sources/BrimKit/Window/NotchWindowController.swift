import AppKit
import QuartzCore
import SwiftUI

/// Owns one screen's window and its pure state machine. The window frame is always exactly the visible
/// panel, so anything outside it falls through to the menu bar or the app below.
@MainActor
final class NotchWindowController {
    let screenID: String
    private let window: NotchWindow
    private let geometry: PanelGeometry
    private let panelState: PanelStateModel
    private let machine: PanelStateMachine

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

        // A notched screen's collapsed window is invisible and sits right over the notch; letting it take
        // mouse events would steal clicks from the menu bar. The global pointer monitor still sees hovers.
        window.ignoresMouseEvents = geometry.isNotched
        machine.onStateChange = { [weak self] state in
            self?.apply(state, animated: true)
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
        window.orderOut(nil)
        window.close()
    }

    // MARK: - Window frame

    private func apply(_ state: PanelState, animated: Bool) {
        panelState.state = state
        window.ignoresMouseEvents = state == .collapsed && geometry.isNotched

        let target = Self.appKitFrame(for: geometry.frame(for: state))
        guard animated else {
            window.setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = state == .expanded ? 0.34 : 0.24
            // Slight overshoot so the panel feels like it grows out of the notch.
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.28, 1.0)
            window.animator().setFrame(target, display: true)
        }
        Log.window.debug("State \(state.rawValue, privacy: .public) on \(self.screenID, privacy: .public)")
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
