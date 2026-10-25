import Foundation

/// Permissions a module can need. Adding a case here means adding a real check in `SystemPermissionService`
/// and an explanation in the module that asks for it.
public enum PermissionKind: String, Codable, CaseIterable, Sendable {
    case automation
    case accessibility
    case calendar
    case mediaAccess

    public var title: String {
        switch self {
        case .automation: "Automation"
        case .accessibility: "Accessibility"
        case .calendar: "Calendar"
        case .mediaAccess: "Now Playing"
        }
    }
}

public enum PermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailable
}
