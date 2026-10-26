import SwiftUI

/// The peek line. It hides completely when no agent has reported anything, the same way media hides.
struct AgentCompactView: View {
    @ObservedObject var module: AgentModule

    var body: some View {
        if let headline = module.summary.headline, let first = module.sessions.first {
            HStack(spacing: 8) {
                AgentStatusGlyph(status: headline, size: 12)

                VStack(alignment: .leading, spacing: 1) {
                    Text(primaryLine(headline: headline, first: first))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(secondaryLine(headline: headline, first: first))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                if module.sessions.count > 1 {
                    Text("\(module.sessions.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(headline: headline, first: first))
        }
    }

    private func primaryLine(headline: AgentStatus, first: AgentSession) -> String {
        module.sessions.count == 1 ? first.agentName : "\(module.sessions.count) agents"
    }

    private func secondaryLine(headline: AgentStatus, first: AgentSession) -> String {
        "\(headline.title) · \(first.displayTitle)"
    }

    private func accessibilityLabel(headline: AgentStatus, first: AgentSession) -> String {
        let summary = module.summary
        var parts: [String] = []
        if summary.waiting > 0 { parts.append("\(summary.waiting) waiting for input") }
        if summary.working > 0 { parts.append("\(summary.working) working") }
        if summary.errors > 0 { parts.append("\(summary.errors) failed") }
        if summary.done > 0 { parts.append("\(summary.done) done") }
        let counts = parts.isEmpty ? headline.title : parts.joined(separator: ", ")
        return "Agents, \(counts). \(first.agentName), \(first.displayTitle)"
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
