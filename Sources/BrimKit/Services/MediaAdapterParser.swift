import Foundation

/// What one line of the adapter's `stream` output means.
public enum MediaAdapterEvent: Equatable, Sendable {
    /// Not JSON, or not a `type: data` envelope. Non-fatal; the stream keeps going.
    case ignored
    /// The adapter is running but no player is reporting anything.
    case noMedia
    case update(NowPlaying)
}

/// Applies the adapter's diff protocol. A line with `diff: false` replaces the whole state; a diff line
/// merges changed keys and removes keys whose value is `null`. Keeping state here means a second of
/// playback only carries the fields that actually changed.
public struct MediaAdapterDecoder {
    private var state: [String: Any] = [:]

    public init() {}

    /// Forgets the previous track, e.g. after restarting the helper process.
    public mutating func reset() {
        state.removeAll()
    }

    public mutating func consume(line: String, receivedAt: Date = Date()) -> MediaAdapterEvent {
        guard
            let data = line.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            root["type"] as? String == "data",
            let payload = root["payload"] as? [String: Any]
        else {
            return .ignored
        }

        if root["diff"] as? Bool == true {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload.filter { !($0.value is NSNull) }
        }

        return event(receivedAt: receivedAt)
    }

    private func event(receivedAt: Date) -> MediaAdapterEvent {
        guard
            let bundleIdentifier = string("bundleIdentifier"),
            !bundleIdentifier.isEmpty
        else {
            return .noMedia
        }
        // The adapter's own test client simulates media without a bundle identifier. Treat that as silence
        // rather than inventing a player.
        guard let title = string("title")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return .noMedia
        }

        let timestamp = double("timestamp").map(Date.init(timeIntervalSince1970:))
        let capturedAt = timestamp.flatMap { abs($0.timeIntervalSince(receivedAt)) < 86_400 ? $0 : nil }
            ?? receivedAt
        let artworkData = string("artworkData").flatMap { Data(base64Encoded: $0) }
        let artwork = artworkData.map {
            NowPlayingArtwork(data: $0, mimeType: string("artworkMimeType"))
        }

        return .update(
            NowPlaying(
                title: title,
                artist: string("artist") ?? "",
                album: string("album") ?? "",
                duration: max(0, double("duration") ?? 0),
                elapsed: max(0, double("elapsedTime") ?? 0),
                capturedAt: capturedAt,
                isPlaying: bool("playing") ?? ((double("playbackRate") ?? 0) > 0),
                source: NowPlayingSource(bundleIdentifier: bundleIdentifier),
                artwork: artwork
            )
        )
    }

    private func string(_ key: String) -> String? {
        guard let value = state[key], !(value is NSNull) else { return nil }
        return value as? String
    }

    private func double(_ key: String) -> Double? {
        if let number = state[key] as? NSNumber { return number.doubleValue }
        if let string = state[key] as? String { return Double(string) }
        return nil
    }

    private func bool(_ key: String) -> Bool? {
        if let value = state[key] as? Bool { return value }
        if let number = state[key] as? NSNumber { return number.boolValue }
        return nil
    }
}
