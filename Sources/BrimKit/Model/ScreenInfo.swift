import CoreGraphics

/// One display, expressed in CoreGraphics global space (origin top-left of the primary display).
public struct ScreenInfo: Identifiable, Equatable, Sendable {
    /// Stable across reconfigurations so a window can be matched to its screen.
    public var id: String
    public var frame: CGRect
    /// Width of the menu bar area to the left of the notch, when the display reports one.
    public var auxiliaryLeftWidth: CGFloat?
    /// Width of the menu bar area to the right of the notch, when the display reports one.
    public var auxiliaryRightWidth: CGFloat?
    /// `NSScreen.safeAreaInsets.top`; non-zero only on displays with a notch (and in some full-screen cases).
    public var topInset: CGFloat

    public init(
        id: String = "screen",
        frame: CGRect,
        auxiliaryLeftWidth: CGFloat? = nil,
        auxiliaryRightWidth: CGFloat? = nil,
        topInset: CGFloat = 0
    ) {
        self.id = id
        self.frame = frame
        self.auxiliaryLeftWidth = auxiliaryLeftWidth
        self.auxiliaryRightWidth = auxiliaryRightWidth
        self.topInset = topInset
    }

    /// The hardware notch, or nil on a display without one.
    ///
    /// macOS exposes no notch rectangle directly. The two auxiliary menu bar areas sit beside it, so the gap
    /// between them is the notch; its height is the safe-area top inset. Derived in one place so every window
    /// agrees on where the notch is.
    public var notchRect: CGRect? {
        guard topInset > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth else { return nil }
        let width = frame.width - left - right
        guard width > 0, width < frame.width else { return nil }
        return CGRect(x: frame.minX + left, y: frame.minY, width: width, height: topInset)
    }

    public var hasNotch: Bool { notchRect != nil }
}
