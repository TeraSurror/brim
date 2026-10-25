import AppKit

/// A panel that floats above the menu bar, joins every Space, and never becomes key or activates Brim.
final class NotchWindow: NSPanel {
    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        worksWhenModal = true
    }

    /// The panel must never take keyboard focus away from the app the user is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// macOS normally keeps a window's title bar below the menu bar. The panel is borderless and has to
    /// occupy the menu bar strip, so bypass the constraint entirely.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
