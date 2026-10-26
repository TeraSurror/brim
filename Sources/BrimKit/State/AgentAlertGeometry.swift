import CoreGraphics

/// Where the notch alert sits, in CoreGraphics global space. It hangs from the top edge like the panel, so it
/// reads as the notch dropping down. Kept pure so placement can be tested without creating a window.
public enum AgentAlertGeometry {
    public static let width: CGFloat = 360
    /// The card below the notch (or below the top edge on a display without one).
    public static let contentHeight: CGFloat = 64

    public static func frame(for screen: ScreenInfo) -> CGRect {
        let width = min(width, max(160, screen.frame.width - 24))
        let centerX = screen.notchRect?.midX ?? screen.frame.midX
        let x = min(max(screen.frame.minX + 8, centerX - width / 2), screen.frame.maxX - 8 - width)
        return CGRect(x: x, y: screen.frame.minY, width: width, height: screen.topInset + contentHeight)
    }

    /// The screen the user is looking at: the one under the pointer, else the notched one, else the first.
    public static func screen(for pointer: CGPoint?, in screens: [ScreenInfo]) -> ScreenInfo? {
        if let pointer, let match = screens.first(where: { $0.frame.contains(pointer) }) {
            return match
        }
        return screens.first(where: \.hasNotch) ?? screens.first
    }
}
