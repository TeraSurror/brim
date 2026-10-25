import Foundation

/// Everything the media module needs. The coordinator behind this owns the helper process, the optional
/// Apple Events path and the user's preferred player; tests use a fake.
@MainActor
public protocol NowPlayingProviding: AnyObject {
    /// The track Brim should show, already resolved against the user's preference.
    var current: NowPlaying? { get }
    /// Installed players the user can follow directly (Spotify and Music today).
    var sources: [NowPlayingSource] { get }
    /// False when neither the MediaRemote helper nor an Automation path can report anything.
    var isAvailable: Bool { get }

    var onUpdate: ((NowPlaying?) -> Void)? { get set }
    var onSourcesChange: (([NowPlayingSource]) -> Void)? { get set }

    /// Starts the helper (and the preferred player's poll) while a panel is visible.
    func startMonitoring()
    func stopMonitoring()
    /// `nil` follows whatever macOS reports; otherwise the bundle identifier of an installed player.
    func follow(_ sourceID: String?)
    func send(_ command: PlayerCommand)
    func seek(to position: TimeInterval)
}
