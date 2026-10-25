import Foundation

/// Automation is real from M2 on because following Spotify or Music directly needs it. The MediaRemote
/// helper does not need a permission, and a denied Automation request leaves the media module working in
/// its adapter-only form.
public struct SystemPermissionService: PermissionRequesting {
    public init() {}

    @MainActor
    public func status(for kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .automation:
            return AutomationPermission.aggregate(ask: false)
        case .accessibility, .calendar, .mediaAccess:
            return .notDetermined
        }
    }

    @MainActor
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        switch kind {
        case .automation:
            // macOS can only ask about a target that is running, so this may return unavailable when the
            // user has neither Spotify nor Music open. It is retried when a player is chosen.
            return AutomationPermission.aggregate(ask: true)
        case .accessibility, .calendar, .mediaAccess:
            Log.general.info(
                "Permission request for \(kind.rawValue, privacy: .public) is not wired up yet")
            return .unavailable
        }
    }
}
