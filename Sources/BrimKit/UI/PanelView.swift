import SwiftUI

/// Everything drawn inside a notch window. The view is deliberately unaware of `NSPanel`; the window
/// controller decides how big the window is, and this view fills it.
struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var panel: PanelStateModel
    let isNotched: Bool
    let topInset: CGFloat
    let peekSize: CGSize
    let expandedSize: CGSize
    let openSettings: () -> Void
    let quit: () -> Void

    private var topPadding: CGFloat {
        isNotched ? topInset + 12 : 12
    }

    /// Fade the incoming layout in with a tiny lift; the outgoing one just fades so the two layouts do
    /// not appear to slide through each other.
    private var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 6)),
            removal: .opacity
        )
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
                ZStack(alignment: .top) {
                    if panel.content == .peek {
                        // Keep each layout at its own target width so the window growth does not
                        // reflow the content while it is animating.
                        peekContent
                            .frame(width: peekSize.width, height: peekSize.height, alignment: .top)
                            .transition(contentTransition)
                    }
                    if panel.content == .expanded {
                        expandedContent
                            .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                            .transition(contentTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.spring(response: 0.34, dampingFraction: 0.88), value: panel.content)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        // Near-black so the panel reads as the notch continuing downward, not a dark grey card.
        let fill = LinearGradient(
            colors: [
                Color.black,
                Color(white: 0.022),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        return shape
            .fill(fill)
            .overlay(shape.strokeBorder(Color.white.opacity(0.055), lineWidth: 1))
            .clipShape(shape)
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
                    .foregroundStyle(.white.opacity(0.38))

                Spacer(minLength: 8)

                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.045)))
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
