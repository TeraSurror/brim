import SwiftUI

/// Everything drawn inside a notch window. The view is deliberately unaware of `NSPanel`; the window
/// controller decides how big the window is, and this view fills it.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var panel: PanelStateModel
    let isNotched: Bool
    let topInset: CGFloat
    let openSettings: () -> Void
    let quit: () -> Void

    private var topPadding: CGFloat {
        isNotched ? topInset + 12 : 12
    }

    var body: some View {
        ZStack(alignment: .top) {
            if panel.state == .collapsed {
                if isNotched {
                    Color.clear
                } else {
                    handle
                }
            } else {
                chrome
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: panel.state)
        .contextMenu {
            Button("Settings…") { openSettings() }
            Divider()
            Button("Quit Brim") { quit() }
        }
    }

    // MARK: - Collapsed

    /// On a display without a notch the collapsed panel is a small, visible grab handle.
    private var handle: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.92))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .frame(width: 72, height: 4)
            .padding(.top, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityLabel("Brim panel")
            .accessibilityHint("Hover or click to open")
    }

    // MARK: - Open panel

    private var chrome: some View {
        let shape = NotchPanelShape(bottomRadius: 28)
        let fill = LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.015, blue: 0.02),
                Color(red: 0.07, green: 0.07, blue: 0.085),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            .clipShape(shape)
    }

    @ViewBuilder
    private var content: some View {
        if panel.state == .peek {
            peekContent
        } else {
            expandedContent
        }
    }

    private var peekContent: some View {
        HStack(spacing: 22) {
            if model.activeModules.isEmpty {
                Text("Brim")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(model.activeModules, id: \.id) { module in
                    module.compactView()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("BRIM")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.3))

                Spacer(minLength: 8)

                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Brim settings")
                .accessibilityLabel("Open Brim settings")
            }
            .padding(.horizontal, 2)

            if model.activeModules.isEmpty {
                emptyModules
            } else {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(model.activeModules, id: \.id) { module in
                        module.expandedView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, topPadding)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var emptyModules: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text("No modules enabled")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            Button("Open Settings…", action: openSettings)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}
