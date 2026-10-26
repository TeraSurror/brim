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
    func applyRetention(minutes: Double)
    func clearFinished()
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

    @Published public private(set) var sessions: [AgentSession] = []
    @Published public private(set) var isListening = false
    public private(set) var isEnabled = false
    public private(set) var retentionMinutes: Double = 10

    public var socketPath: String { listener.socketPath }
    public var sessionCount: Int { sessions.count }
    public var finishedCount: Int { sessions.filter { $0.status == .done || $0.status == .error }.count }
    public var summary: AgentSummary { roster.summary }

    private let listener: AgentEventListening
    private let now: () -> Date
    private var roster: AgentRoster
    private var finishedRetention: TimeInterval

    public init(
        listener: AgentEventListening? = nil,
        roster: AgentRoster = AgentRoster(),
        retentionMinutes: Double = 10,
        now: @escaping () -> Date = Date.init
    ) {
        self.listener = listener ?? AgentSocketService()
        self.roster = roster
        self.now = now
        let clamped = Self.clampRetention(retentionMinutes)
        self.retentionMinutes = clamped
        self.finishedRetention = clamped * 60
        self.listener.onEvent = { [weak self] event in
            self?.ingest(event)
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
            roster.clear()
            sessions = []
        }
    }

    /// Finished sessions expire on the next panel open rather than on a timer, keeping collapsed cost at
    /// zero. Working and waiting sessions stay visible until they change or the user clears them.
    public func setPanelActive(_ active: Bool) {
        guard active, isEnabled else { return }
        let before = roster.sessions
        roster.prune(now: now(), finishedRetention: finishedRetention)
        if roster.sessions != before {
            sessions = roster.sessions
        }
    }

    public func compactView() -> AnyView {
        AnyView(AgentCompactView(module: self))
    }

    public func expandedView() -> AnyView {
        AnyView(AgentExpandedView(module: self))
    }

    // MARK: - Events

    public func ingest(_ event: AgentEvent) {
        guard isEnabled else { return }
        roster.prune(now: now(), finishedRetention: finishedRetention)
        _ = roster.apply(event)
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

    private static func clampRetention(_ minutes: Double) -> Double {
        guard minutes.isFinite else { return 10 }
        return min(max(minutes, Settings.agentRetentionRange.lowerBound), Settings.agentRetentionRange.upperBound)
    }
}
