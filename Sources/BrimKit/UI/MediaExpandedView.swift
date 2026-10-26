import SwiftUI

/// The full panel card: artwork, metadata, a scrubbable progress bar and transport controls. The timeline
/// only runs while this view is on screen, which is also the only time the helper process is alive.
struct MediaExpandedView: View {
    @ObservedObject var module: MediaModule

    @State private var scrubbing: TimeInterval?

    var body: some View {
        Group {
            if let track = module.nowPlaying {
                player(track)
            } else {
                emptyState
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
        )
    }

    private func player(_ track: NowPlaying) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = scrubbing ?? track.position(at: context.date)

            GeometryReader { proxy in
                // The card is a fixed 220 pt tall. Keep the artwork, progress and transport as one
                // vertically centered group so the card has no dead space and the transport is centered
                // on the card rather than on the text column beside the artwork.
                let compact = proxy.size.width < 320
                let artworkSize: CGFloat = compact ? 84 : 96

                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: compact ? 11 : 14) {
                        MediaArtworkView(artwork: track.artwork, size: artworkSize)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(track.title)
                                    .font(.system(size: compact ? 13.5 : 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                sourceMenu(track, compact: compact)
                            }

                            Text(track.artist.isEmpty ? track.source.name : track.artist)
                                .font(.system(size: compact ? 11 : 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)

                            if !compact && !track.album.isEmpty {
                                Text(track.album)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.32))
                                    .lineLimit(1)
                            }

                            sourceLine(track)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    progress(track, position: position)
                    controls(track)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func sourceLine(_ track: NowPlaying) -> some View {
        HStack(spacing: 4) {
            Image(systemName: track.source.symbolName)
                .font(.system(size: 8, weight: .semibold))
            Text("Playing in \(track.source.name)")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.38))
        .accessibilityLabel("Playing in \(track.source.name)")
    }

    // MARK: - Progress

    @ViewBuilder
    private func progress(_ track: NowPlaying, position: TimeInterval) -> some View {
        if track.duration > 0 {
            VStack(spacing: 2) {
                Slider(
                    value: Binding(
                        get: { min(max(position, 0), track.duration) },
                        set: { scrubbing = $0 }
                    ),
                    in: 0...track.duration,
                    onEditingChanged: { editing in
                        guard !editing else { return }
                        if let scrubbing { module.seek(to: scrubbing) }
                        scrubbing = nil
                    }
                )
                .controlSize(.mini)
                .tint(.white.opacity(0.85))
                .accessibilityLabel("Playback position")
                .accessibilityValue(timeLabel(position))

                HStack {
                    Text(timeLabel(position))
                    Spacer()
                    Text("-\(timeLabel(max(0, track.duration - position)))")
                }
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.38))
            }
        }
    }

    // MARK: - Controls

    private func controls(_ track: NowPlaying) -> some View {
        HStack(spacing: 16) {
            Spacer(minLength: 0)

            transportButton("backward.fill", label: "Previous track", size: 11) {
                module.send(.previous)
            }

            Button {
                module.send(.togglePlayPause)
            } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help(track.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(track.isPlaying ? "Pause" : "Play")

            transportButton("forward.fill", label: "Next track", size: 11) {
                module.send(.next)
            }

            Spacer(minLength: 0)
        }
    }

    private func transportButton(
        _ symbol: String,
        label: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: - Source

    private func sourceMenu(_ track: NowPlaying, compact: Bool) -> some View {
        Menu {
            Button {
                module.choosePlayer(nil)
            } label: {
                menuLabel("Automatic (macOS)", selected: module.preferredSourceID == nil)
            }

            if !module.sources.isEmpty {
                Divider()
                ForEach(module.sources) { source in
                    Button {
                        module.choosePlayer(source.id)
                    } label: {
                        menuLabel(source.name, selected: module.preferredSourceID == source.id)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: track.source.symbolName)
                    .font(.system(size: 8, weight: .semibold))
                if !compact {
                    Text(track.source.name)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.42))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose the player Brim follows; grant Automation in Settings if asked")
        .accessibilityLabel("Player to follow")
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text("Start something in Spotify, Music or Safari.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing playing")
    }

    private func timeLabel(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
