import CryptoKit
import Foundation

/// The app that owns a track. `id` is the bundle identifier so settings, the adapter and Apple Events can
/// all refer to the same player.
public struct NowPlayingSource: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let symbolName: String

    public init(id: String, name: String, symbolName: String = "play.circle") {
        self.id = id
        self.name = name
        self.symbolName = symbolName
    }

    /// Falls back to a readable last path component for players Brim has never heard of.
    public init(bundleIdentifier: String) {
        if let known = Self.known[bundleIdentifier] {
            self = known
            return
        }
        let component = bundleIdentifier.split(separator: ".").last.map(String.init) ?? bundleIdentifier
        let name = component
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        self.init(id: bundleIdentifier, name: name, symbolName: "play.circle")
    }

    public static let spotify = NowPlayingSource(
        id: "com.spotify.client", name: "Spotify", symbolName: "music.note")
    public static let music = NowPlayingSource(
        id: "com.apple.Music", name: "Music", symbolName: "music.note")
    public static let safari = NowPlayingSource(
        id: "com.apple.Safari", name: "Safari", symbolName: "safari")

    private static let known: [String: NowPlayingSource] = [
        spotify.id: spotify,
        music.id: music,
        safari.id: safari,
        "com.apple.Music.Music": music,
        "com.google.Chrome": NowPlayingSource(
            id: "com.google.Chrome", name: "Chrome", symbolName: "globe"),
        "com.microsoft.edgemac": NowPlayingSource(
            id: "com.microsoft.edgemac", name: "Edge", symbolName: "globe"),
        // Several browsers end their bundle ID in "Browser", so the fallback name would be ambiguous.
        "com.brave.Browser": NowPlayingSource(
            id: "com.brave.Browser", name: "Brave", symbolName: "globe"),
        "company.thebrowser.Browser": NowPlayingSource(
            id: "company.thebrowser.Browser", name: "Arc", symbolName: "globe"),
        "org.mozilla.firefox": NowPlayingSource(
            id: "org.mozilla.firefox", name: "Firefox", symbolName: "globe"),
        "com.operasoftware.Opera": NowPlayingSource(
            id: "com.operasoftware.Opera", name: "Opera", symbolName: "globe"),
        "com.vivaldi.Vivaldi": NowPlayingSource(
            id: "com.vivaldi.Vivaldi", name: "Vivaldi", symbolName: "globe"),
        "com.apple.QuickTimePlayerX": NowPlayingSource(
            id: "com.apple.QuickTimePlayerX", name: "QuickTime Player", symbolName: "film"),
        "com.apple.TV": NowPlayingSource(
            id: "com.apple.TV", name: "TV", symbolName: "tv"),
        "com.apple.podcasts": NowPlayingSource(
            id: "com.apple.podcasts", name: "Podcasts", symbolName: "mic"),
        "com.colliderli.iina": NowPlayingSource(
            id: "com.colliderli.iina", name: "IINA", symbolName: "play.rectangle"),
        "org.videolan.vlc": NowPlayingSource(
            id: "org.videolan.vlc", name: "VLC", symbolName: "play.rectangle"),
    ]
}

/// Artwork plus a content hash. Equality and the image cache use the hash so a one-second progress update
/// never compares or re-decodes a few hundred kilobytes of image data.
public struct NowPlayingArtwork: Sendable {
    public let data: Data
    public let mimeType: String?
    public let id: String

    public init(data: Data, mimeType: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension NowPlayingArtwork: Equatable {
    public static func == (lhs: NowPlayingArtwork, rhs: NowPlayingArtwork) -> Bool {
        lhs.id == rhs.id && lhs.mimeType == rhs.mimeType
    }
}

/// One snapshot of playback. `elapsed` was true at `capturedAt`, so the view can interpolate smoothly
/// between updates without any extra timers.
public struct NowPlaying: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var capturedAt: Date
    public var isPlaying: Bool
    public var source: NowPlayingSource
    public var artwork: NowPlayingArtwork?

    public init(
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        capturedAt: Date = Date(),
        isPlaying: Bool = false,
        source: NowPlayingSource,
        artwork: NowPlayingArtwork? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.capturedAt = capturedAt
        self.isPlaying = isPlaying
        self.source = source
        self.artwork = artwork
    }

    public func position(at date: Date) -> TimeInterval {
        let raw = isPlaying ? elapsed + max(0, date.timeIntervalSince(capturedAt)) : elapsed
        guard duration > 0 else { return max(0, raw) }
        return min(max(0, raw), duration)
    }

    public func remaining(at date: Date) -> TimeInterval {
        guard duration > 0 else { return 0 }
        return max(0, duration - position(at: date))
    }
}

public enum PlayerCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
}
