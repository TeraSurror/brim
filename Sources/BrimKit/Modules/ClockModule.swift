import SwiftUI

/// M1's placeholder module: a glanceable clock. It updates once a minute and only exists in the view tree
/// while the panel is visible, so a collapsed notch costs nothing.
@MainActor
public final class ClockModule: BrimModule {
    public let id = "clock"
    public let title = "Clock"
    public let symbolName = "clock"
    public let requiredPermissions: [PermissionKind] = []
    public let permissionExplanation = ""
    public private(set) var isEnabled = false

    public init() {}

    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    public func compactView() -> AnyView {
        AnyView(ClockCompactView())
    }

    public func expandedView() -> AnyView {
        AnyView(ClockExpandedView())
    }
}

private struct ClockCompactView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .semibold))
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white.opacity(0.92))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Time")
        }
    }
}

private struct ClockExpandedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NOW")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.35))

            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(22)
        // Center the clock group in the card; leaving all of the slack under the date made the expanded
        // panel look half empty next to the media card.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: .leading, vertical: .center))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.055), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Clock")
    }
}
