import SwiftUI

/// The peek strip: artwork against the left edge, the track in the middle, the indicator against the
/// right edge. It stays out of the way when nothing is playing.
struct MediaCompactView: View {
    @ObservedObject var module: MediaModule

    var body: some View {
        if let track = module.nowPlaying {
            HStack(spacing: 9) {
                MediaArtworkView(artwork: track.artwork, size: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(subtitle(for: track))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                EqualizerIndicator(isPlaying: track.isPlaying)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(for: track))
        }
    }

    private func subtitle(for track: NowPlaying) -> String {
        track.artist.isEmpty ? track.source.name : track.artist
    }

    private func accessibilityLabel(for track: NowPlaying) -> String {
        var parts = [track.title]
        if !track.artist.isEmpty { parts.append("by \(track.artist)") }
        parts.append(track.isPlaying ? "playing" : "paused")
        return parts.joined(separator: ", ")
    }
}
