import AppKit

/// Real implementations of the small system-facing protocols.

public struct DispatchScheduler: Scheduling {
    public init() {}

    @MainActor
    public func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> TaskHandle {
        let work = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: work)
        return TaskHandle { work.cancel() }
    }
}

public struct NSScreenProvider: ScreenProviding {
    public init() {}

    @MainActor
    public var screens: [ScreenInfo] {
        guard let primary = NSScreen.screens.first else { return [] }
        let primaryHeight = primary.frame.height
        return NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.frame
            // NSScreen uses bottom-left of the primary; ScreenInfo uses CoreGraphics top-left global space.
            let cgFrame = CGRect(
                x: frame.minX,
                y: primaryHeight - frame.maxY,
                width: frame.width,
                height: frame.height
            )
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return ScreenInfo(
                id: number.map { "display-\($0.uint32Value)" } ?? "screen-\(index)",
                frame: cgFrame,
                auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
                auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
                topInset: screen.safeAreaInsets.top
            )
        }
    }
}
