import AppKit
import Carbon
import Foundation

/// The two players Brim can talk to directly. Everything else (Safari, Chrome, QuickTime, …) is only
/// available through the system-wide MediaRemote helper.
public enum ScriptablePlayer: String, CaseIterable, Equatable, Sendable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    public var source: NowPlayingSource {
        switch self {
        case .spotify: .spotify
        case .music: .music
        }
    }

    public var applicationName: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Music"
        }
    }

    /// Spotify's AppleScript `duration` is milliseconds; Music's is seconds.
    var durationIsMilliseconds: Bool { self == .spotify }
}

@MainActor
public protocol PlayerAutomationControlling: AnyObject {
    func isPermitted(for player: ScriptablePlayer) -> Bool
    func snapshot(of player: ScriptablePlayer) -> NowPlaying?
    func send(_ command: PlayerCommand, to player: ScriptablePlayer)
    func seek(to position: TimeInterval, in player: ScriptablePlayer)
}

@MainActor
public protocol PlayerDiscovering {
    var installedPlayers: [ScriptablePlayer] { get }
    func isRunning(_ player: ScriptablePlayer) -> Bool
}

public struct InstalledPlayerDiscovery: PlayerDiscovering {
    public nonisolated init() {}

    public var installedPlayers: [ScriptablePlayer] {
        ScriptablePlayer.allCases.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.rawValue) != nil
        }
    }

    public func isRunning(_ player: ScriptablePlayer) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty
    }
}

/// Reads and controls Spotify and Music with Apple Events. This is the optional path: Brim only follows
/// one of these players when the user picks it and only runs a script while that player is running with
/// Automation granted, so Brim never launches an app behind the user's back.
@MainActor
public final class AppleEventsPlayerAutomation: PlayerAutomationControlling {
    private let discovery: PlayerDiscovering
    private var scripts: [String: NSAppleScript] = [:]
    private var artworkCache: [ScriptablePlayer: (key: String, artwork: NowPlayingArtwork?)] = [:]

    public init(discovery: PlayerDiscovering = InstalledPlayerDiscovery()) {
        self.discovery = discovery
    }

    public func isPermitted(for player: ScriptablePlayer) -> Bool {
        AutomationPermission.status(forBundleIdentifier: player.rawValue, ask: false) == .granted
    }

    public func snapshot(of player: ScriptablePlayer) -> NowPlaying? {
        guard discovery.isRunning(player), isPermitted(for: player) else { return nil }
        guard let result = execute(Self.snapshotScript(for: player)), result.numberOfItems >= 6 else {
            return nil
        }

        let state = (result.atIndex(1)?.stringValue ?? "").lowercased()
        guard state != "stopped" else { return nil }
        let title = (result.atIndex(2)?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let artist = result.atIndex(3)?.stringValue ?? ""
        let album = result.atIndex(4)?.stringValue ?? ""
        var duration = result.atIndex(5)?.doubleValue ?? 0
        if player.durationIsMilliseconds { duration /= 1000 }
        let elapsed = max(0, result.atIndex(6)?.doubleValue ?? 0)

        return NowPlaying(
            title: title,
            artist: artist,
            album: album,
            duration: max(0, duration),
            elapsed: elapsed,
            capturedAt: Date(),
            isPlaying: state == "playing",
            source: player.source,
            artwork: artwork(for: player, title: title, artist: artist, album: album)
        )
    }

    public func send(_ command: PlayerCommand, to player: ScriptablePlayer) {
        guard discovery.isRunning(player), isPermitted(for: player) else { return }
        _ = execute(commandScript(command, for: player))
    }

    public func seek(to position: TimeInterval, in player: ScriptablePlayer) {
        guard discovery.isRunning(player), isPermitted(for: player) else { return }
        let seconds = String(format: "%.3f", max(0, position))
        _ = execute("tell application \"\(player.applicationName)\" to set player position to \(seconds)")
    }

    // MARK: - Scripts

    private static func snapshotScript(for player: ScriptablePlayer) -> String {
        """
        tell application "\(player.applicationName)"
            if player state is stopped then return {}
            set currentTrack to current track
            return {player state as text, name of currentTrack, artist of currentTrack, album of currentTrack, duration of currentTrack, player position}
        end tell
        """
    }

    private static let musicArtworkScript = """
        tell application "Music"
            try
                return data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """

    private func commandScript(_ command: PlayerCommand, for player: ScriptablePlayer) -> String {
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        return "tell application \"\(player.applicationName)\" to \(verb)"
    }

    /// Artwork is only fetched when the track changes; polling once a second should not pull the image
    /// repeatedly. Spotify's scripting dictionary has no artwork data, so it relies on the adapter instead.
    private func artwork(
        for player: ScriptablePlayer,
        title: String,
        artist: String,
        album: String
    ) -> NowPlayingArtwork? {
        guard player == .music else { return nil }
        let key = "\(title)|\(artist)|\(album)"
        if let cached = artworkCache[player], cached.key == key { return cached.artwork }

        var artwork: NowPlayingArtwork?
        if let result = execute(Self.musicArtworkScript), result.descriptorType == typeData {
            let data = result.data
            if !data.isEmpty {
                artwork = NowPlayingArtwork(data: data)
            }
        }
        artworkCache[player] = (key, artwork)
        return artwork
    }

    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else if let compiled = NSAppleScript(source: source) {
            scripts[source] = compiled
            script = compiled
        } else {
            Log.media.error("Could not compile an Apple Events script")
            return nil
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
            Log.media.error("Apple Events failed: \(message, privacy: .public)")
            return nil
        }
        return result
    }
}
