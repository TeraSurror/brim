import SwiftUI

/// One ear of the live notch while media plays: the artwork on the left, the playing indicator on the right.
/// The shell sizes the ear; this view only centers its content in it.
struct MediaLiveView: View {
    @ObservedObject var module: MediaModule
    let edge: LiveActivityEdge

    var body: some View {
        if let track = module.nowPlaying {
            Group {
                switch edge {
                case .leading:
                    MediaArtworkView(artwork: track.artwork, size: 20)
                case .trailing:
                    EqualizerIndicator(isPlaying: track.isPlaying)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: track))
        }
    }

    private func accessibilityLabel(for track: NowPlaying) -> String {
        var parts = [track.title]
        if !track.artist.isEmpty { parts.append("by \(track.artist)") }
        parts.append("from \(track.source.name)")
        parts.append(track.isPlaying ? "playing" : "paused")
        return parts.joined(separator: ", ")
    }
}
