import AppKit
import SwiftUI

/// A short-lived card under the notch. Used when macOS won't deliver a notification (notably ad-hoc dev
/// builds), so the opt-in alert still works. It never activates Brim or steals keyboard focus.
@MainActor
public final class AgentAlertPresenter: AgentAlertPresenting {
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

        guard let screen = screens.screens.first(where: { $0.hasNotch }) ?? screens.screens.first else {
            return
        }
        let cgFrame = AgentAlertGeometry.frame(for: screen)
        let window = NotchWindow(frame: Self.appKitFrame(for: cgFrame))
        window.hasShadow = true
        window.alphaValue = 0

        let root = AgentAlertView(
            notification: notification,
            onOpen: { [weak self] in
                onOpen()
                self?.dismiss()
            },
            onDismiss: { [weak self] in self?.dismiss() }
        )
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }

        self.window = window
        dismissTask = scheduler.schedule(after: 7) { [weak self] in
            self?.dismiss()
        }
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
}
