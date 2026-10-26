import Combine
import SwiftUI

/// Narrow surface `AppModel` needs from the agent module: retention and cleanup without knowing the
/// concrete module type in tests.
@MainActor
public protocol AgentModuleControlling: AnyObject {
    var socketPath: String { get }
    var isListening: Bool { get }
    var sessionCount: Int { get }
    var finishedCount: Int { get }
    var notificationsEnabled: Bool { get }
    var notificationAuthorization: NotificationAuthorization { get }
    func applyRetention(minutes: Double)
    func clearFinished()
    func setNotificationsEnabled(_ enabled: Bool)
    func refreshNotificationAuthorization() async
    func requestNotificationAuthorization() async -> NotificationAuthorization
    func open(_ session: AgentSession)
    /// Adds a sample waiting session, so the user can check the panel and alerts without a real agent.
    func showTestSession()
}

/// Shows what local AI tools are doing. The module owns the socket listener, but all aggregation is in the
/// pure `AgentRoster`; no timer runs while the panel is collapsed.
@MainActor
public final class AgentModule: BrimModule, AgentModuleControlling, ObservableObject {
    public static let moduleID = "agents"

    public let id = AgentModule.moduleID
    public let title = "Agent Status"
    public let symbolName = "sparkles"
    public let requiredPermissions: [PermissionKind] = []
    public let permissionExplanation = ""

    @Published public private(set) var sessions: [AgentSession] = [] {
        didSet { updateLiveActivity() }
    }
    @Published public private(set) var liveActivity: LiveActivity?
    @Published public private(set) var isListening = false
    @Published public private(set) var notificationAuthorization: NotificationAuthorization = .notDetermined
    public private(set) var isEnabled = false
    public private(set) var retentionMinutes: Double = 10
    public private(set) var notificationsEnabled = false

    public var socketPath: String { listener.socketPath }
    public var sessionCount: Int { sessions.count }
    public var finishedCount: Int { sessions.filter { $0.status == .done || $0.status == .error }.count }
    public var summary: AgentSummary { roster.summary }

    private let listener: AgentEventListening
    private let notifier: AgentNotifying
    private let workspace: WorkspaceOpening
    private let alertPresenter: AgentAlertPresenting?
    private let now: () -> Date
    private let notificationTracker = AgentNotificationTracker()
    private var roster: AgentRoster
    private var finishedRetention: TimeInterval
    private var panelActive = false
    /// Failed sessions the user has seen in the open panel. They stay listed but stop lighting the notch.
    private var acknowledgedErrors: Set<String> = []

    public init(
        listener: AgentEventListening? = nil,
        notifier: AgentNotifying? = nil,
        workspace: WorkspaceOpening? = nil,
        alertPresenter: AgentAlertPresenting? = nil,
        roster: AgentRoster = AgentRoster(),
        retentionMinutes: Double = 10,
        notificationsEnabled: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.listener = listener ?? AgentSocketService()
        self.notifier = notifier ?? UserNotificationService()
        self.workspace = workspace ?? WorkspaceService()
        self.alertPresenter = alertPresenter
        self.roster = roster
        self.now = now
        let clamped = Self.clampRetention(retentionMinutes)
        self.retentionMinutes = clamped
        self.finishedRetention = clamped * 60
        self.notificationsEnabled = notificationsEnabled
        self.notificationAuthorization = self.notifier.authorization
        self.listener.onEvent = { [weak self] event in
            self?.ingest(event)
        }
        self.notifier.onOpen = { [weak self] target in
            self?.open(target)
        }
    }

    // MARK: - BrimModule

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            listener.onEvent = { [weak self] event in self?.ingest(event) }
            listener.start()
            isListening = listener.isListening
            if !isListening {
                Log.agent.error("Agent socket failed to start")
            }
        } else {
            listener.stop()
            isListening = false
            alertPresenter?.dismiss()
            roster.clear()
            sessions = []
        }
    }

    /// Finished sessions expire on the next panel open rather than on a timer, keeping collapsed cost at
    /// zero. Working and waiting sessions stay visible until they change or the user clears them.
    public func setPanelActive(_ active: Bool) {
        panelActive = active
        guard active, isEnabled else { return }
        // The open panel shows the same session, and the alert would sit on top of it.
        alertPresenter?.dismiss()
        let before = roster.sessions
        roster.prune(now: now(), finishedRetention: finishedRetention)
        if roster.sessions != before {
            sessions = roster.sessions
        }
        acknowledgedErrors.formUnion(sessions.filter { $0.status == .error }.map(\.id))
        updateLiveActivity()
    }

    public var liveActivityPublisher: AnyPublisher<LiveActivity?, Never> {
        $liveActivity.eraseToAnyPublisher()
    }

    public func liveView(_ edge: LiveActivityEdge) -> AnyView {
        AnyView(AgentLiveView(module: self, edge: edge))
    }

    /// The status the live notch shows: waiting first, then a failure the user has not seen, then working.
    /// Finished sessions never light the notch.
    public var liveStatus: AgentStatus? {
        if sessions.contains(where: { $0.status == .waiting }) { return .waiting }
        if sessions.contains(where: { $0.status == .error && !acknowledgedErrors.contains($0.id) }) {
            return .error
        }
        if sessions.contains(where: { $0.status == .working }) { return .working }
        return nil
    }

    /// How many sessions share `liveStatus`, for the count in the right ear.
    public var liveCount: Int {
        guard let status = liveStatus else { return 0 }
        return sessions.filter {
            $0.status == status && !(status == .error && acknowledgedErrors.contains($0.id))
        }.count
    }

    private func updateLiveActivity() {
        // An acknowledgement lasts only while the session stays failed; failing again later lights it again.
        acknowledgedErrors.formIntersection(sessions.filter { $0.status == .error }.map(\.id))
        let next: LiveActivity?
        switch liveStatus {
        case .waiting, .error: next = LiveActivity(priority: .attention)
        case .working: next = LiveActivity(priority: .ambient)
        case .done, nil: next = nil
        }
        if next != liveActivity { liveActivity = next }
    }

    public func expandedView() -> AnyView {
        AnyView(AgentExpandedView(module: self))
    }

    // MARK: - Events

    public func ingest(_ event: AgentEvent) {
        guard isEnabled else { return }
        let key = AgentSession.key(agentID: event.agentID, sessionID: event.sessionID)
        let previousStatus = roster.sessions.first { $0.id == key }?.status
        roster.prune(now: now(), finishedRetention: finishedRetention)
        _ = roster.apply(event)
        if let session = roster.sessions.first(where: { $0.id == key }) {
            maybeNotify(session, previousStatus: previousStatus)
        }
        sessions = roster.sessions
        Log.agent.debug(
            "Agent \(event.agentID, privacy: .public) \(event.sessionID, privacy: .public) is \(event.status.rawValue, privacy: .public)"
        )
    }

    public func handle(_ command: AgentCommand) {
        guard isEnabled else { return }
        switch command {
        case .event(let event):
            ingest(event)
        case .dismiss(let agentID, let sessionID):
            roster.dismiss(id: AgentSession.key(agentID: agentID, sessionID: sessionID))
            sessions = roster.sessions
        case .clear:
            roster.clear()
            sessions = []
        }
    }

    public func dismiss(_ session: AgentSession) {
        roster.dismiss(id: session.id)
        sessions = roster.sessions
    }

    public func clearFinished() {
        roster.clearFinished()
        sessions = roster.sessions
    }

    public func clearAll() {
        roster.clear()
        sessions = []
    }

    public func applyRetention(minutes: Double) {
        let clamped = Self.clampRetention(minutes)
        retentionMinutes = clamped
        finishedRetention = clamped * 60
        roster.prune(now: now(), finishedRetention: finishedRetention)
        sessions = roster.sessions
    }

    // MARK: - Notifications and project opening

    public func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        if !enabled {
            alertPresenter?.dismiss()
        }
    }

    public func refreshNotificationAuthorization() async {
        await notifier.refreshAuthorization()
        notificationAuthorization = notifier.authorization
    }

    public func requestNotificationAuthorization() async -> NotificationAuthorization {
        let status = await notifier.requestAuthorization()
        notificationAuthorization = status
        return status
    }

    public func showTestSession() {
        guard let event = AgentEvent(
            agentID: "brim",
            sessionID: "test",
            status: .waiting,
            title: "Test session",
            detail: "Agent Status works. Dismiss this row when you're done.",
            timestamp: now()
        ) else { return }
        ingest(event)
    }

    /// Takes the user back to a session: the app running it when known and installed, otherwise its
    /// project folder in Finder.
    public func open(_ session: AgentSession) {
        open(session.openTarget)
    }

    private func open(_ target: AgentOpenTarget) {
        if let app = target.app, workspace.activateApplication(bundleIdentifier: app) { return }
        if let cwd = target.cwd { _ = workspace.openDirectory(cwd) }
    }

    private func maybeNotify(_ session: AgentSession, previousStatus: AgentStatus?) {
        guard notificationsEnabled else { return }
        guard let notification = notificationTracker.notification(
            for: session,
            previousStatus: previousStatus,
            panelActive: panelActive
        ) else { return }

        if notifier.authorization.isAuthorized {
            notifier.post(notification)
        } else {
            // Ad-hoc dev builds cannot get a notification permission prompt; the notch alert keeps the
            // opt-in feature working and matches the panel's visual language.
            alertPresenter?.present(notification) { [weak self] in
                self?.open(notification.target)
            }
        }
    }

    private static func clampRetention(_ minutes: Double) -> Double {
        guard minutes.isFinite else { return 10 }
        return min(max(minutes, Settings.agentRetentionRange.lowerBound), Settings.agentRetentionRange.upperBound)
    }
}
