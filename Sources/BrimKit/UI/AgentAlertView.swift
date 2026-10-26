import SwiftUI

/// The content of the notch alert. Black like the panel, with a folder action when a project is known.
struct AgentAlertView: View {
    let notification: AgentNotification
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AgentStatusGlyph(status: notification.status, size: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(notification.body)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if notification.cwd?.isEmpty == false {
                Button(action: onOpen) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open project in Finder")
                .accessibilityLabel("Open project in Finder")
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss agent alert")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notification.title), \(notification.body)")
    }
}
