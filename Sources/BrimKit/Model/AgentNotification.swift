import Foundation

/// Where clicking an agent alert or row takes the user: the app running the session when it is known,
/// otherwise the project folder in Finder.
public struct AgentOpenTarget: Equatable, Sendable {
    public let app: String?
    public let cwd: String?

    public init(app: String?, cwd: String?) {
        self.app = app?.isEmpty == true ? nil : app
        self.cwd = cwd?.isEmpty == true ? nil : cwd
    }

    public var isEmpty: Bool { app == nil && cwd == nil }
}

/// A local notification the agent module wants to show. The open target is carried through so clicking
/// the notification can take the user back to the session that needs attention.
public struct AgentNotification: Equatable, Sendable {
    public let title: String
    public let body: String
    public let sessionID: String
    public let target: AgentOpenTarget
    public let status: AgentStatus

    public init(title: String, body: String, sessionID: String, target: AgentOpenTarget, status: AgentStatus) {
        self.title = title
        self.body = body
        self.sessionID = sessionID
        self.target = target
        self.status = status
    }
}

public enum NotificationAuthorization: String, Sendable {
    case notDetermined
    case denied
    case authorized

    public var isAuthorized: Bool { self == .authorized }

    public var title: String {
        switch self {
        case .notDetermined: "Notifications not requested"
        case .denied: "Notifications disabled"
        case .authorized: "Notifications allowed"
        }
    }
}
