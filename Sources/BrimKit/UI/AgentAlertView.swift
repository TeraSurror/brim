import SwiftUI

/// The content of the notch alert. Drawn with the panel's shape and black so it reads as the notch dropping
/// down; the whole card performs the open action, and the close button only dismisses.
struct AgentAlertView: View {
    let notification: AgentNotification
    /// Height of the notch on this screen; the card's content sits below it.
    let topInset: CGFloat
    let onOpen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        let shape = NotchPanelShape(bottomRadius: 20)
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

            if let symbol = openSymbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityHidden(true)
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
        .padding(.horizontal, 16)
        .padding(.top, topInset + 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Color.black))
        .overlay(shape.strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(shape)
        .onTapGesture(perform: onOpen)
        .help(openHelp ?? "")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notification.title), \(notification.body)")
        .accessibilityAction(named: openHelp ?? "Open") { onOpen() }
    }

    private var openSymbol: String? {
        if notification.target.app != nil { return "arrow.up.forward.app" }
        if notification.target.cwd != nil { return "folder" }
        return nil
    }

    private var openHelp: String? {
        if notification.target.app != nil { return "Switch to the app running this session" }
        if notification.target.cwd != nil { return "Open the project in Finder" }
        return nil
    }
}
