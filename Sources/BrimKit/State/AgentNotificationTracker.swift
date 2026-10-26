import Foundation

/// Decides whether a session transition deserves a notification. It is stateless: the module supplies
/// the status before the event, which is enough to avoid repeating a waiting notification.
public struct AgentNotificationTracker: Sendable {
    public init() {}

    public func notification(
        for session: AgentSession,
        previousStatus: AgentStatus?,
        panelActive: Bool
    ) -> AgentNotification? {
        guard !panelActive, session.status != previousStatus else { return nil }

        switch session.status {
        case .waiting, .error:
            break
        case .working, .done:
            return nil
        }

        let title = session.status == .waiting
            ? "\(session.agentName) needs your input"
            : "\(session.agentName) failed"
        let detail = session.detail.isEmpty ? session.displayTitle : "\(session.displayTitle) — \(session.detail)"
        return AgentNotification(
            title: title,
            body: String(detail.prefix(180)),
            sessionID: session.id,
            target: session.openTarget,
            status: session.status
        )
    }
}
