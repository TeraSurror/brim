import CoreGraphics
import Foundation

/// A cancelable scheduled callback. `Scheduling` exists so `State/` can be driven by a fake clock in tests.
public final class TaskHandle: @unchecked Sendable {
    private let onCancel: () -> Void
    public private(set) var isCancelled = false

    public init(onCancel: @escaping () -> Void = {}) {
        self.onCancel = onCancel
    }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        onCancel()
    }
}

public protocol Scheduling {
    @discardableResult
    @MainActor func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> TaskHandle
}

public protocol ScreenProviding {
    @MainActor var screens: [ScreenInfo] { get }
}

/// Global pointer position and clicks, in CoreGraphics global space. Running only while the app needs it.
public protocol PointerMonitoring: AnyObject {
    @MainActor var onMove: ((CGPoint) -> Void)? { get set }
    @MainActor var onLeftClick: ((CGPoint) -> Void)? { get set }
    @MainActor func start()
    @MainActor func stop()
}

public protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public protocol SettingsPersisting {
    func load() -> Settings
    func save(_ settings: Settings)
}

/// Every permission request goes through here. Modules ask only after the user sees an explanation.
public protocol PermissionRequesting {
    @MainActor func status(for kind: PermissionKind) -> PermissionStatus
    @MainActor func request(_ kind: PermissionKind) async -> PermissionStatus
}
