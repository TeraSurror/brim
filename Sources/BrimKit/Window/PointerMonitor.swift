import AppKit

/// Reads the pointer from global and local mouse events. Global events cover other apps and spaces;
/// local events cover Brim's own non-activating panel, which global monitors deliberately skip.
/// No Accessibility permission is needed for mouse events, and nothing polls.
@MainActor
public final class NSEventPointerMonitor: PointerMonitoring {
    public var onMove: ((CGPoint) -> Void)?
    public var onLeftClick: ((CGPoint) -> Void)?
    public var onScroll: ((ScrollSample) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    public init() {}

    public func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .scrollWheel]

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
        switch event.type {
        case .leftMouseDown:
            onLeftClick?(point)
        case .scrollWheel:
            onScroll?(Self.sample(from: event, at: point))
        default:
            onMove?(point)
        }
    }

    /// Undoes "natural scrolling" so the deltas follow the fingers: fingers down is always positive Y.
    private static func sample(from event: NSEvent, at point: CGPoint) -> ScrollSample {
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let phase: ScrollSample.Phase
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            phase = .began
        } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            phase = .ended
        } else if event.phase.isEmpty {
            phase = .none
        } else {
            phase = .changed
        }
        return ScrollSample(
            location: point,
            deltaX: event.scrollingDeltaX * sign,
            deltaY: event.scrollingDeltaY * sign,
            phase: phase,
            isMomentum: !event.momentumPhase.isEmpty,
            timestamp: event.timestamp
        )
    }

    /// CoreGraphics global space: origin top-left of the primary display, matching `ScreenInfo.frame`.
    private static func cgPoint(from point: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}
