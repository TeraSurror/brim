import SwiftUI

/// The expanded card. Rows are ordered by urgency (waiting first), so the thing that needs the user is at
/// the top even when several agents are running.
struct AgentExpandedView: View {
    @ObservedObject var module: AgentModule

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if module.sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    // Elapsed labels stay useful while the panel is open without paying for a timer when
                    // it is collapsed; this view only exists in the expanded layout.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(spacing: 6) {
                            ForEach(module.sessions) { session in
                                AgentSessionRow(
                                    session: session,
                                    now: context.date,
                                    onOpen: { module.open(session) },
                                    onDismiss: { module.dismiss(session) }
                                )
                            }
                        }
                    }
                }
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

    private var header: some View {
        HStack(spacing: 8) {
            Text("AGENTS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.35))

            if let headline = module.summary.headline {
                Text(headline.title)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(headline.color.opacity(0.9))
            }

            Spacer(minLength: 4)

            if module.finishedCount > 0 {
                Button {
                    module.clearFinished()
                } label: {
                    Text("Clear")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.45))
                .help("Clear finished and failed sessions")
                .accessibilityLabel("Clear finished agent sessions")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("No agent activity")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Text(emptyMessage)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No agent activity")
    }

    private var emptyMessage: String {
        if module.isListening {
            return "Claude Code and other tools report here over the local socket."
        }
        if module.isEnabled {
            return "The agent socket could not start. Check the Brim log."
        }
        return "Enable the Agent Status module in Settings."
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    let now: Date
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AgentStatusGlyph(status: session.status, size: 11)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let cost = session.costText {
                        Text(cost)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.38))
                    }
                }

                if !session.detail.isEmpty {
                    Text(session.detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("\(session.agentName) · \(session.status.title)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(session.status.color.opacity(0.72))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(session.elapsedText(now: now))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)

            if let action = openAction {
                Button(action: onOpen) {
                    Image(systemName: action.symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(action.help)
                .accessibilityLabel("\(action.help): \(session.agentName), \(session.displayTitle)")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss \(session.displayTitle)")
            .accessibilityLabel("Dismiss \(session.agentName) session \(session.displayTitle)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint)
        )
    }

    /// The app wins when known; the module falls back to the folder if that app is no longer installed.
    private var openAction: (symbol: String, help: String)? {
        if session.app != nil { return ("arrow.up.forward.app", "Switch to the app running this session") }
        if session.cwd != nil { return ("folder", "Open the project in Finder") }
        return nil
    }

    private var tint: Color {
        switch session.status {
        case .waiting: .orange.opacity(0.10)
        case .error: .red.opacity(0.09)
        case .working: .white.opacity(0.045)
        case .done: .white.opacity(0.025)
        }
    }

    private var accessibilityLabel: String {
        var parts = [session.agentName, session.displayTitle, session.status.title]
        if !session.detail.isEmpty { parts.append(session.detail) }
        parts.append(session.elapsedText(now: now))
        if let cost = session.costText { parts.append(cost) }
        return parts.joined(separator: ", ")
    }
}
