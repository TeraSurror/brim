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

    /// Only a panel opened from the keyboard (or a field that asks to type) may take keyboard focus. The
    /// panel is non-activating, so even then the front app keeps its menu bar and stays active.
    var acceptsKeyboardFocus = false
    var onCancel: (() -> Void)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeyboardFocus }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Esc is taken here, before a focused text field can treat it as "complete", so it always means
    /// "back out": the panel decides whether that leaves a conversation or closes it.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]) {
            onCancel?()
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// macOS normally keeps a window's title bar below the menu bar. The panel is borderless and has to
    /// occupy the menu bar strip, so bypass the constraint entirely.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
