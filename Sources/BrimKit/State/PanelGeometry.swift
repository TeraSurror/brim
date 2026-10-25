import CoreGraphics
import Foundation

/// Sizes for every panel state. Kept as a value type so tests can use recorded screen data and a custom layout.
public struct PanelMetrics: Equatable, Sendable {
    /// Height of the strip shown on the first hover.
    public var peekHeight: CGFloat
    public var expandedWidth: CGFloat
    public var expandedHeight: CGFloat
    /// The peek is never narrower than this, even on a display with a very narrow notch.
    public var minimumPeekWidth: CGFloat
    /// Space added on each side of the notch in the peek so the panel reads as wider than the notch.
    public var peekNotchPadding: CGFloat
    /// The visible handle on displays without a notch.
    public var handleSize: CGSize
    /// Keeps an expanded panel off the screen edges.
    public var screenMargin: CGFloat

    public init(
        peekHeight: CGFloat = 84,
        expandedWidth: CGFloat = 600,
        expandedHeight: CGFloat = 320,
        minimumPeekWidth: CGFloat = 360,
        peekNotchPadding: CGFloat = 48,
        handleSize: CGSize = CGSize(width: 148, height: 10),
        screenMargin: CGFloat = 16
    ) {
        self.peekHeight = peekHeight
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
        self.minimumPeekWidth = minimumPeekWidth
        self.peekNotchPadding = peekNotchPadding
        self.handleSize = handleSize
        self.screenMargin = screenMargin
    }
}

/// Pure layout for one display. All rectangles are in CoreGraphics global space (origin top-left of the
/// primary display), so the window layer only has to convert once when it sets an AppKit frame.
public struct PanelGeometry: Equatable, Sendable {
    public let screen: ScreenInfo
    public let metrics: PanelMetrics

    public init(screen: ScreenInfo, metrics: PanelMetrics = PanelMetrics()) {
        self.screen = screen
        self.metrics = metrics
    }

    public var isNotched: Bool { screen.notchRect != nil }

    public var collapsedFrame: CGRect {
        if let notch = screen.notchRect { return notch }
        let width = min(metrics.handleSize.width, max(1, availableWidth))
        return CGRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.minY,
            width: width,
            height: metrics.handleSize.height
        )
    }

    public var peekWidth: CGFloat {
        let notchWidth = screen.notchRect?.width ?? 0
        let desired = max(metrics.minimumPeekWidth, notchWidth + metrics.peekNotchPadding * 2)
        return min(desired, availableWidth)
    }

    public var expandedPanelWidth: CGFloat {
        min(metrics.expandedWidth, availableWidth)
    }

    public func frame(for state: PanelState) -> CGRect {
        switch state {
        case .collapsed:
            return collapsedFrame
        case .peek:
            return topAnchored(width: peekWidth, height: metrics.peekHeight)
        case .expanded:
            return topAnchored(width: expandedPanelWidth, height: metrics.expandedHeight)
        }
    }

    /// The area that keeps a state open. The exit area is deliberately bigger than the entry area so a
    /// pointer that brushes the edge on the way to the menu bar does not make the panel flicker.
    public func hitRect(for state: PanelState, slop: CGFloat) -> CGRect {
        frame(for: state).insetBy(dx: -slop, dy: -slop)
    }

    public func contains(_ point: CGPoint, in state: PanelState, slop: CGFloat = 0) -> Bool {
        hitRect(for: state, slop: slop).contains(point)
    }

    private var availableWidth: CGFloat {
        max(1, screen.frame.width - metrics.screenMargin * 2)
    }

    private func topAnchored(width: CGFloat, height: CGFloat) -> CGRect {
        let clampedHeight = min(height, max(1, screen.frame.height))
        let clampedWidth = max(1, width)
        return CGRect(
            x: screen.frame.midX - clampedWidth / 2,
            y: screen.frame.minY,
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

/// User-tunable hover/collapse timing plus internal tolerances.
public struct PanelTimings: Equatable, Sendable {
    /// Delay before the peek appears (Settings → hover delay).
    public var hoverDelay: TimeInterval
    /// How long the peek must stay up before it grows on its own. Clicking skips this.
    public var expandDelay: TimeInterval
    /// Delay before collapsing after the pointer leaves (Settings → collapse delay).
    public var collapseDelay: TimeInterval
    /// Extra room around the expanded panel before it counts as "left".
    public var exitSlop: CGFloat

    public init(
        hoverDelay: TimeInterval = 0.15,
        expandDelay: TimeInterval = 0.7,
        collapseDelay: TimeInterval = 0.4,
        exitSlop: CGFloat = 12
    ) {
        self.hoverDelay = hoverDelay
        self.expandDelay = expandDelay
        self.collapseDelay = collapseDelay
        self.exitSlop = exitSlop
    }
}
