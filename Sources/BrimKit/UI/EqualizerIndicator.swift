import SwiftUI

/// The playing indicator on the right edge of the peek. The symbol effect runs only in the view tree
/// while the peek is visible.
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
