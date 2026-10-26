import SwiftUI

/// The notch's ears for Quick Prompt: a quiet glyph while Claude works, then the outcome until the panel opens.
struct QuickPromptLiveView: View {
    @ObservedObject var module: QuickPromptModule
    let edge: LiveActivityEdge

    var body: some View {
        if let state = module.liveState {
            Group {
                switch edge {
                case .leading:
                    Image(systemName: "text.bubble.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .symbolEffect(.pulse, options: .repeating, isActive: state == .running)
                case .trailing:
                    trailing(state)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(state))
        }
    }

    @ViewBuilder
    private func trailing(_ state: PromptTurn.State) -> some View {
        switch state {
        case .running:
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
        case .stopped:
            Image(systemName: "stop.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func label(_ state: PromptTurn.State) -> String {
        switch state {
        case .running: return "Quick Prompt: Claude is answering"
        case .done: return "Quick Prompt: answer ready"
        case .failed: return "Quick Prompt: failed"
        case .stopped: return "Quick Prompt: stopped"
        }
    }
}
