import SwiftUI

/// The playing indicator in the live notch's right ear. The symbol effect runs only while it is in the view
/// tree and the track is playing.
struct EqualizerIndicator: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(isPlaying ? 0.85 : 0.45))
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isPlaying)
            .frame(width: 16)
            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}
