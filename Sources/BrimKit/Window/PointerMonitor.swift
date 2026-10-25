import AppKit

/// Reads the pointer from global and local mouse events. Global events cover other apps and spaces;
/// local events cover Brim's own non-activating panel, which global monitors deliberately skip.
/// No Accessibility permission is needed for mouse events, and nothing polls.
@MainActor
public final class NSEventPointerMonitor: PointerMonitoring {
    public var onMove: ((CGPoint) -> Void)?
    public var onLeftClick: ((CGPoint) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

    public func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    public func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let point = Self.cgPoint(from: NSEvent.mouseLocation)
        if event.type == .leftMouseDown {
            onLeftClick?(point)
        } else {
            onMove?(point)
        }
    }

    /// CoreGraphics global space: origin top-left of the primary display, matching `ScreenInfo.frame`.
    private static func cgPoint(from point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
