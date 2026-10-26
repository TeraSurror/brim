import AppKit
import SwiftUI

/// Owns the settings window. The panel windows belong to `Window/`, not here.
@MainActor
final class WindowPresenter {
    private var settingsWindow: NSWindow?

    func showSettings(model: AppModel) {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView().environmentObject(model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Brim Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.setContentSize(NSSize(width: 600, height: 560))
            // `NSWindow.center()` picks the screen of the app's key window, which can be a different
            // display than the panel the user just clicked. Follow the pointer instead.
            centerOnPointerScreen(window)
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func centerOnPointerScreen(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.screens.first
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }
}
