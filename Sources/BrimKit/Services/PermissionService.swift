import Foundation

/// M1 has no module that needs a real permission. M2 replaces each case with the matching system check
/// (Automation for Music/Spotify, the now-playing probe for media) while keeping the explanation flow in
/// `AppModel` unchanged.
public struct SystemPermissionService: PermissionRequesting {
    public init() {}

    @MainActor
    public func status(for kind: PermissionKind) -> PermissionStatus {
        .notDetermined
    }

    @MainActor
    public func request(_ kind: PermissionKind) async -> PermissionStatus {
        Log.general.info("Permission request for \(kind.rawValue, privacy: .public) is not wired up in M1")
        return .unavailable
    }
}
