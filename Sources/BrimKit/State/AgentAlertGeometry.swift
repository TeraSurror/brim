import CoreGraphics

/// Where the notch alert sits, in CoreGraphics global space. Kept pure so the placement can be tested
/// without creating a window.
public enum AgentAlertGeometry {
    public static let size = CGSize(width: 360, height: 72)

    public static func frame(for screen: ScreenInfo, size: CGSize = size) -> CGRect {
        let width = min(size.width, max(160, screen.frame.width - 24))
        let centeredX = (screen.notchRect?.midX ?? screen.frame.midX) - width / 2
        let x = max(screen.frame.minX + 8, centeredX)
        let y = (screen.notchRect?.maxY ?? screen.frame.minY) + 8
        return CGRect(x: x, y: y, width: width, height: size.height)
    }
}
