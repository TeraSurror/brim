import Carbon
import Foundation

/// macOS grants Automation per (Brim, player) pair. `AEDeterminePermissionToAutomateTarget` can ask for
/// consent without sending an event, so Brim never has to launch Spotify or Music just to prompt.
///
/// A player that is not running reports `procNotFound`; that is not a denial. Brim simply has no Automation
/// work to do until the player runs again.
enum AutomationPermission {
    static func status(forBundleIdentifier identifier: String, ask: Bool) -> PermissionStatus {
        var address = AEAddressDesc()
        let created = identifier.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, strlen($0), &address)
        }
        guard created == noErr else { return .unavailable }
        defer { AEDisposeDesc(&address) }

        let result = AEDeterminePermissionToAutomateTarget(
            &address,
            AEEventClass(typeWildCard),
            AEEventID(typeWildCard),
            ask
        )
        switch result {
        case noErr:
            return .granted
        case OSStatus(errAEEventWouldRequireUserConsent):
            return .notDetermined
        case OSStatus(errAEEventNotPermitted):
            return .denied
        case OSStatus(procNotFound):
            return .unavailable
        default:
            return .unavailable
        }
    }

    /// `granted` if any player is allowed, so one denial does not hide a working player.
    static func aggregate(ask: Bool) -> PermissionStatus {
        let statuses = ScriptablePlayer.allCases.map {
            status(forBundleIdentifier: $0.rawValue, ask: ask)
        }
        if statuses.contains(.granted) { return .granted }
        if statuses.contains(.notDetermined) { return .notDetermined }
        if statuses.contains(.denied) { return .denied }
        return .unavailable
    }
}
