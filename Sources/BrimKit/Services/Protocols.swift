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

/// Local agent events, delivered over a Unix socket. The listener starts only while the agent module is
/// enabled; `onEvent` is called on the main actor with input that has already been validated.
@MainActor
public protocol AgentEventListening: AnyObject {
    var socketPath: String { get }
    var isListening: Bool { get }
    var onEvent: ((AgentEvent) -> Void)? { get set }
    func start()
    func stop()
}

/// Local notifications for agent transitions. Permission is requested only from the settings toggle,
/// never at launch; `post` is a no-op until authorization is granted.
@MainActor
public protocol AgentNotifying: AnyObject {
    var authorization: NotificationAuthorization { get }
    var onOpenProject: ((String) -> Void)? { get set }
    func refreshAuthorization() async
    func requestAuthorization() async -> NotificationAuthorization
    func post(_ notification: AgentNotification)
}

/// Opening a project without letting the agent module touch AppKit directly.
@MainActor
public protocol WorkspaceOpening: AnyObject {
    func openDirectory(_ path: String) -> Bool
}

/// Brim's own alert shown under the notch when macOS notifications are unavailable or denied. This keeps
/// the opt-in feature working for ad-hoc development builds.
@MainActor
public protocol AgentAlertPresenting: AnyObject {
    func present(_ notification: AgentNotification, onOpen: @escaping () -> Void)
    func dismiss()
}
