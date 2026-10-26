import SwiftUI

/// One ear of the live notch for agents: the most urgent status on the left, how many sessions share it on
/// the right. It only exists while an agent is waiting, failing or working.
struct AgentLiveView: View {
    @ObservedObject var module: AgentModule
    let edge: LiveActivityEdge

    var body: some View {
        if let status = module.liveStatus {
            Group {
                switch edge {
                case .leading:
                    AgentStatusGlyph(status: status, size: 13)
                        .symbolEffect(.pulse, options: .repeating, isActive: status == .working)
                case .trailing:
                    if module.liveCount > 1 {
                        Text("\(module.liveCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(status.color)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(status: status))
        }
    }

    private func accessibilityLabel(status: AgentStatus) -> String {
        let count = module.liveCount
        return count > 1 ? "\(count) agents: \(status.title)" : "Agent: \(status.title)"
    }
}

struct AgentStatusGlyph: View {
    let status: AgentStatus
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: status.symbolName)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(status.color)
            .accessibilityHidden(true)
    }
}

extension AgentStatus {
    var symbolName: String {
        switch self {
        case .working: "circle.dotted"
        case .waiting: "exclamationmark.circle.fill"
        case .done: "checkmark.circle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .working: .white.opacity(0.85)
        case .waiting: .orange
        case .done: .green
        case .error: .red
        }
    }
}
