import AppKit
import CoreGraphics

/// One on-screen window as the window server reports it. Bounds are in CoreGraphics global space, the same
/// space as `ScreenInfo.frame`.
public struct WindowSnapshot: Equatable, Sendable {
    public var ownerPID: pid_t
    public var layer: Int
    public var bounds: CGRect
    public var alpha: Double

    public init(ownerPID: pid_t, layer: Int, bounds: CGRect, alpha: Double = 1) {
        self.ownerPID = ownerPID
        self.layer = layer
        self.bounds = bounds
        self.alpha = alpha
    }
}

/// Finds full-screen apps from the window list. Size alone cannot tell full screen from a zoomed window: on a
/// notched display a full-screen window stops below the menu bar strip, exactly where a zoomed one does. A
/// full-screen Space has no desktop, though, so Finder's and WindowManager's desktop-level windows for that
/// display leave the window list while it is in front. Window bounds, levels and owners need no Screen
/// Recording permission; only window titles do, and they are never read.
@MainActor
public final class WorkspaceFullScreenMonitor: FullScreenDetecting {
    /// The full-screen animation finishes after the Space change is announced, so look again once it settles.
    private static let settleDelays: [TimeInterval] = [0.4, 1.2]

    public private(set) var coveredScreenIDs: Set<String> = []
    public var onChange: ((Set<String>) -> Void)?

    private let screens: ScreenProviding
    private let scheduler: Scheduling
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var settleTasks: [TaskHandle] = []

    public init(screens: ScreenProviding = NSScreenProvider(), scheduler: Scheduling = DispatchScheduler()) {
        self.screens = screens
        self.scheduler = scheduler
    }

    public func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observe(name, on: workspace)
        }
        observe(NSApplication.didChangeScreenParametersNotification, on: .default)
        refresh()
    }

    public func stop() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        cancelSettleTasks()
        update([])
    }

    /// Screens showing a Space with no desktop, filled by a normal-level window of another app.
    public static func coveredScreenIDs(
        windows: [WindowSnapshot],
        screens: [ScreenInfo],
        excludingPID ownPID: pid_t
    ) -> Set<String> {
        let desktopLayer = Int(CGWindowLevelForKey(.desktopIconWindow))
        let desktops = windows.filter { $0.layer == desktopLayer }
        let appWindows = windows.filter { $0.ownerPID != ownPID && $0.layer == 0 && $0.alpha > 0 }
        return Set(screens.filter { screen in
            let topStrip = max(screen.topInset, screen.menuBarHeight)
            return !desktops.contains { covers($0.bounds, screen.frame, allowingTopStrip: 0) }
                && appWindows.contains { covers($0.bounds, screen.frame, allowingTopStrip: topStrip) }
        }.map(\.id))
    }

    /// True when `bounds` fills `screen`, optionally leaving the menu bar strip uncovered.
    private static func covers(_ bounds: CGRect, _ screen: CGRect, allowingTopStrip topStrip: CGFloat) -> Bool {
        let tolerance: CGFloat = 1
        return bounds.minX <= screen.minX + tolerance
            && bounds.minY <= screen.minY + topStrip + tolerance
            && bounds.maxX >= screen.maxX - tolerance
            && bounds.maxY >= screen.maxY - tolerance
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceMayHaveChanged() }
        }
        observers.append((center, observer))
    }

    private func spaceMayHaveChanged() {
        refresh()
        cancelSettleTasks()
        settleTasks = Self.settleDelays.map { delay in
            scheduler.schedule(after: delay) { [weak self] in self?.refresh() }
        }
    }

    private func cancelSettleTasks() {
        for task in settleTasks { task.cancel() }
        settleTasks.removeAll()
    }

    private func refresh() {
        let windows = Self.onScreenWindows()
        Log.window.debug("Full-screen check over \(windows.count, privacy: .public) window(s)")
        let covered = Self.coveredScreenIDs(
            windows: windows,
            screens: screens.screens,
            excludingPID: ProcessInfo.processInfo.processIdentifier
        )
        update(covered)
    }

    private func update(_ covered: Set<String>) {
        guard covered != coveredScreenIDs else { return }
        coveredScreenIDs = covered
        Log.window.info("Full-screen screens: \(covered.sorted().joined(separator: ", "), privacy: .public)")
        onChange?(covered)
    }

    private static func onScreenWindows() -> [WindowSnapshot] {
        // Desktop elements stay in: their absence is the signal.
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
            else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            return WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds, alpha: alpha)
        }
    }
}
