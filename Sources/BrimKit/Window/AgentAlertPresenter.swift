import AppKit
import SwiftUI

/// A short-lived card that drops from the top edge of the screen the user is on. Used when macOS won't
/// deliver a notification (notably ad-hoc dev builds), so the opt-in alert still works. It never activates
/// Brim or steals keyboard focus, and it stays while the pointer rests on it.
@MainActor
public final class AgentAlertPresenter: AgentAlertPresenting {
    public static let displayDuration: TimeInterval = 7
    /// Time left after the pointer moves off a card it had paused.
    public static let resumeDuration: TimeInterval = 3

    private let screens: ScreenProviding
    private let scheduler: Scheduling
    private var window: NotchWindow?
    private var dismissTask: TaskHandle?

    public init(screens: ScreenProviding = NSScreenProvider(), scheduler: Scheduling = DispatchScheduler()) {
        self.screens = screens
        self.scheduler = scheduler
    }

    public func present(_ notification: AgentNotification, onOpen: @escaping () -> Void) {
        dismiss()

        let pointer = Self.cgPoint(from: NSEvent.mouseLocation)
        guard let screen = AgentAlertGeometry.screen(for: pointer, in: screens.screens) else { return }
        let cgFrame = AgentAlertGeometry.frame(for: screen)
        let window = NotchWindow(frame: Self.appKitFrame(for: cgFrame))
        window.hasShadow = true
        window.alphaValue = 0

        let root = AgentAlertView(
            notification: notification,
            topInset: screen.topInset,
            onOpen: { [weak self] in
                onOpen()
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        let hosting = PanelHostingView(rootView: root)
        hosting.onMouseEntered = { [weak self] in
            self?.dismissTask?.cancel()
            self?.dismissTask = nil
        }
        hosting.onMouseExited = { [weak self] in
            self?.scheduleDismiss(after: Self.resumeDuration)
        }
        window.contentView = hosting
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }

        self.window = window
        scheduleDismiss(after: Self.displayDuration)
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let window else { return }
        self.window = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        } completionHandler: {
            window.orderOut(nil)
            window.close()
        }
    }

    private func scheduleDismiss(after delay: TimeInterval) {
        guard window != nil else { return }
        dismissTask?.cancel()
        dismissTask = scheduler.schedule(after: delay) { [weak self] in
            self?.dismiss()
        }
    }

    /// Converts the pure CoreGraphics frame (top-left origin) to AppKit's bottom-left screen space.
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
