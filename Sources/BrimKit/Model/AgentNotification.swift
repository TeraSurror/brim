import Foundation

/// A local notification the agent module wants to show. `cwd` is carried through so clicking the
/// notification can open the project that needs attention.
public struct AgentNotification: Equatable, Sendable {
    public let title: String
    public let body: String
    public let sessionID: String
    public let cwd: String?
    public let status: AgentStatus

    public init(title: String, body: String, sessionID: String, cwd: String?, status: AgentStatus) {
        self.title = title
        self.body = body
        self.sessionID = sessionID
        self.cwd = cwd
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
