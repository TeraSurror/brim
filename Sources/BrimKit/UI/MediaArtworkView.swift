import AppKit
import SwiftUI

/// Artwork with a subtle placeholder. Images are decoded once per content hash, so the once-a-second
/// progress updates never touch the decoder.
struct MediaArtworkView: View {
    let artwork: NowPlayingArtwork?
    let size: CGFloat

    private var cornerRadius: CGFloat { max(4, size * 0.16) }

    var body: some View {
        ZStack {
            if let artwork, let image = ArtworkImageCache.shared.image(for: artwork) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.17), Color(white: 0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: size * 0.34, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

@MainActor
final class ArtworkImageCache {
    static let shared = ArtworkImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 12
        // A few large covers cannot grow the collapsed app past the memory budget.
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func image(for artwork: NowPlayingArtwork) -> NSImage? {
        let key = artwork.id as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = NSImage(data: artwork.data) else { return nil }
        cache.setObject(image, forKey: key, cost: artwork.data.count)
        return image
    }

    /// Called when monitoring stops: the panel is collapsing, so the decoded covers are no longer needed.
    func clear() {
        cache.removeAllObjects()
    }
}
