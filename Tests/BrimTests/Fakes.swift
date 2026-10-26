import CoreGraphics
import Foundation
import SwiftUI
@testable import BrimKit

@MainActor
final class FakeScheduler: Scheduling {
    struct Pending {
        let due: TimeInterval
        let action: @MainActor () -> Void
        let handle: TaskHandle
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Pending] = []

    var pendingCount: Int { pending.filter { !$0.handle.isCancelled }.count }

    func schedule(after interval: TimeInterval, _ action: @escaping @MainActor () -> Void) -> TaskHandle {
        let handle = TaskHandle {}
        pending.append(Pending(due: now + interval, action: action, handle: handle))
        return handle
    }

    func advance(by interval: TimeInterval) {
        let target = now + interval
        while let next = pending
            .filter({ !$0.handle.isCancelled && $0.due <= target })
            .min(by: { $0.due < $1.due }) {
            now = next.due
            pending.removeAll { $0.handle === next.handle }
            next.action()
        }
        now = target
    }
}

struct FakeScreens: ScreenProviding {
    var infos: [ScreenInfo]
    @MainActor var screens: [ScreenInfo] { infos }
}

@MainActor
final class FakePointer: PointerMonitoring {
    var onMove: ((CGPoint) -> Void)?
    var onLeftClick: ((CGPoint) -> Void)?
    private(set) var running = false

    func start() { running = true }
    func stop() { running = false }

    func move(_ x: CGFloat, _ y: CGFloat) { onMove?(CGPoint(x: x, y: y)) }
    func click(_ x: CGFloat, _ y: CGFloat) { onLeftClick?(CGPoint(x: x, y: y)) }
}

struct FakeLoginError: Error {}

final class FakeLoginItems: LoginItemControlling {
    var enabled = false
    var failure: Error?
    private(set) var setCalls: [Bool] = []

    var isEnabled: Bool { enabled }

    func setEnabled(_ enabled: Bool) throws {
        setCalls.append(enabled)
        if let failure { throw failure }
        self.enabled = enabled
    }
}

final class FakeSettingsStore: SettingsPersisting {
    // SwiftUI also declares a `Settings` scene; qualify Brim's value type in this file.
    var stored: BrimKit.Settings
    private(set) var saves: [BrimKit.Settings] = []

    init(_ settings: BrimKit.Settings = BrimKit.Settings()) {
        self.stored = settings
    }

    func load() -> BrimKit.Settings { stored }

    func save(_ settings: BrimKit.Settings) {
        stored = settings
        saves.append(settings)
    }
}

@MainActor
final class FakePermissions: PermissionRequesting {
    var statuses: [PermissionKind: PermissionStatus] = [:]
    var requestResult: PermissionStatus = .granted
    private(set) var requests: [PermissionKind] = []

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses[kind] ?? .notDetermined
    }

    func request(_ kind: PermissionKind) async -> PermissionStatus {
        requests.append(kind)
        statuses[kind] = requestResult
        return requestResult
    }
}

@MainActor
final class FakeMediaAdapter: MediaAdapterStreaming {
    var onUpdate: ((NowPlaying?) -> Void)?
    var onFailure: ((String) -> Void)?
    var isAvailable = true
    var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var commands: [PlayerCommand] = []
    private(set) var seeks: [TimeInterval] = []

    func start() {
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func send(_ command: PlayerCommand) { commands.append(command) }
    func seek(to position: TimeInterval) { seeks.append(position) }

    func emit(_ track: NowPlaying?) { onUpdate?(track) }
    func fail(_ message: String = "failed") { onFailure?(message) }
}

@MainActor
final class FakePlayerAutomation: PlayerAutomationControlling {
    var permitted = true
    var snapshots: [ScriptablePlayer: NowPlaying] = [:]
    private(set) var reads: [ScriptablePlayer] = []
    private(set) var commands: [(command: PlayerCommand, player: ScriptablePlayer)] = []
    private(set) var seeks: [(position: TimeInterval, player: ScriptablePlayer)] = []

    func isPermitted(for player: ScriptablePlayer) -> Bool { permitted }

    func snapshot(of player: ScriptablePlayer) -> NowPlaying? {
        reads.append(player)
        return snapshots[player]
    }

    func send(_ command: PlayerCommand, to player: ScriptablePlayer) {
        commands.append((command, player))
    }

    func seek(to position: TimeInterval, in player: ScriptablePlayer) {
        seeks.append((position, player))
    }
}

@MainActor
final class FakePlayerDiscovery: PlayerDiscovering {
    var installedPlayers: [ScriptablePlayer]
    var running: Set<ScriptablePlayer>

    init(installed: [ScriptablePlayer] = [.spotify, .music], running: Set<ScriptablePlayer> = [.spotify, .music]) {
        self.installedPlayers = installed
        self.running = running
    }

    func isRunning(_ player: ScriptablePlayer) -> Bool { running.contains(player) }
}

@MainActor
final class FakeNowPlayingService: NowPlayingProviding {
    var current: NowPlaying?
    var sources: [NowPlayingSource] = []
    var isAvailable = true
    var onUpdate: ((NowPlaying?) -> Void)?
    var onSourcesChange: (([NowPlayingSource]) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var followed: [String?] = []
    private(set) var commands: [PlayerCommand] = []
    private(set) var seeks: [TimeInterval] = []

    func startMonitoring() { startCount += 1 }
    func stopMonitoring() { stopCount += 1 }
    func follow(_ sourceID: String?) { followed.append(sourceID) }
    func send(_ command: PlayerCommand) { commands.append(command) }
    func seek(to position: TimeInterval) { seeks.append(position) }

    func emit(_ track: NowPlaying?) {
        current = track
        onUpdate?(track)
    }
}

@MainActor
final class FakeModule: BrimModule {
    let id: String
    let title: String
    let symbolName = "square.dashed"
    let requiredPermissions: [PermissionKind]
    let permissionExplanation: String
    private(set) var isEnabled = false
    private(set) var enableHistory: [Bool] = []
    private(set) var panelActiveHistory: [Bool] = []

    init(id: String, permissions: [PermissionKind] = [], explanation: String = "Explanation") {
        self.id = id
        self.title = id.capitalized
        self.requiredPermissions = permissions
        self.permissionExplanation = explanation
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enableHistory.append(enabled)
    }

    func setPanelActive(_ active: Bool) {
        panelActiveHistory.append(active)
    }

    func compactView() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}


@MainActor
final class FakeMediaControllingModule: BrimModule, MediaModuleControlling {
    let id = "media"
    let title = "Now Playing"
    let symbolName = "play.circle"
    let requiredPermissions: [PermissionKind] = []
    let permissionExplanation = ""
    var sources: [NowPlayingSource] = [.music]
    private(set) var isEnabled = false
    private(set) var appliedPreferences: [String?] = []

    func setEnabled(_ enabled: Bool) { isEnabled = enabled }

    func applyPreferredPlayer(_ sourceID: String?) {
        appliedPreferences.append(sourceID)
    }

    func compactView() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
final class FakeAgentListener: AgentEventListening {
    let socketPath: String
    private(set) var isListening = false
    var onEvent: ((AgentEvent) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(socketPath: String = "/tmp/brim-agent-test.sock") {
        self.socketPath = socketPath
    }

    func start() {
        startCount += 1
        isListening = true
    }

    func stop() {
        stopCount += 1
        isListening = false
    }

    func emit(_ event: AgentEvent) {
        onEvent?(event)
    }
}

@MainActor
final class FakeAgentControllingModule: BrimModule, AgentModuleControlling {
    let id = "agents"
    let title = "Agent Status"
    let symbolName = "sparkles"
    let requiredPermissions: [PermissionKind] = []
    let permissionExplanation = ""
    let socketPath = "/tmp/brim-agent-test.sock"
    var isListening = false
    var sessionCount = 0
    var finishedCount = 0
    var notificationsEnabled = false
    var notificationAuthorization: NotificationAuthorization = .notDetermined
    var requestResult: NotificationAuthorization = .authorized
    private(set) var isEnabled = false
    private(set) var appliedRetention: [Double] = []
    private(set) var clearFinishedCount = 0
    private(set) var notificationRequests = 0
    private(set) var openedProjects: [AgentSession] = []

    func setEnabled(_ enabled: Bool) { isEnabled = enabled }

    func applyRetention(minutes: Double) {
        appliedRetention.append(minutes)
    }

    func clearFinished() {
        clearFinishedCount += 1
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
    }

    func refreshNotificationAuthorization() async {
        if notificationAuthorization == .notDetermined {
            notificationAuthorization = .authorized
        }
    }

    func requestNotificationAuthorization() async -> NotificationAuthorization {
        notificationRequests += 1
        notificationAuthorization = requestResult
        return requestResult
    }

    func openProject(_ session: AgentSession) {
        openedProjects.append(session)
    }

    func compactView() -> AnyView { AnyView(EmptyView()) }
    func expandedView() -> AnyView { AnyView(EmptyView()) }
}

@MainActor
final class FakeAgentNotifier: AgentNotifying {
    var authorization: NotificationAuthorization
    var onOpenProject: ((String) -> Void)?
    private(set) var posted: [AgentNotification] = []
    private(set) var requestCount = 0
    private(set) var refreshCount = 0
    var requestResult: NotificationAuthorization = .authorized

    init(authorization: NotificationAuthorization = .authorized) {
        self.authorization = authorization
    }

    func refreshAuthorization() async {
        refreshCount += 1
    }

    func requestAuthorization() async -> NotificationAuthorization {
        requestCount += 1
        authorization = requestResult
        return authorization
    }

    func post(_ notification: AgentNotification) {
        posted.append(notification)
    }
}

@MainActor
final class FakeWorkspace: WorkspaceOpening {
    var succeeds = true
    private(set) var openedPaths: [String] = []

    func openDirectory(_ path: String) -> Bool {
        openedPaths.append(path)
        return succeeds
    }
}

@MainActor
final class FakeAgentAlertPresenter: AgentAlertPresenting {
    private(set) var presented: [AgentNotification] = []
    private(set) var dismissCount = 0
    private var onOpen: (() -> Void)?

    func present(_ notification: AgentNotification, onOpen: @escaping () -> Void) {
        presented.append(notification)
        self.onOpen = onOpen
    }

    func dismiss() {
        dismissCount += 1
    }

    func openLatest() {
        onOpen?()
    }
}
