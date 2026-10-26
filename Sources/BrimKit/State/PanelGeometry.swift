import CoreGraphics
import Foundation

/// Sizes for every panel state. Kept as a value type so tests can use recorded screen data and a custom layout.
public struct PanelMetrics: Equatable, Sendable {
    public var expandedWidth: CGFloat
    public var expandedHeight: CGFloat
    /// Width added on each side of the hardware notch while a module shows live content.
    public var liveEarWidth: CGFloat
    /// The live pill on a display without a notch. Its height is only a fallback: the pill matches the menu
    /// bar's height when the screen reports one, so it reads as a notch rather than a tab under the menu bar.
    public var livePillSize: CGSize
    /// The visible handle on displays without a notch.
    public var handleSize: CGSize
    /// Keeps an expanded panel off the screen edges.
    public var screenMargin: CGFloat

    public init(
        expandedWidth: CGFloat = 600,
        expandedHeight: CGFloat = 320,
        liveEarWidth: CGFloat = 40,
        livePillSize: CGSize = CGSize(width: 150, height: 24),
        handleSize: CGSize = CGSize(width: 148, height: 10),
        screenMargin: CGFloat = 16
    ) {
        self.expandedWidth = expandedWidth
        self.expandedHeight = expandedHeight
        self.liveEarWidth = liveEarWidth
        self.livePillSize = livePillSize
        self.handleSize = handleSize
        self.screenMargin = screenMargin
    }

    /// Module cards get a fixed share each, so adding a module widens the panel instead of squeezing every card.
    public static let moduleCardWidth: CGFloat = 290
    public static let moduleSpacing: CGFloat = 14
    public static let panelHorizontalPadding: CGFloat = 18
    public static let minimumExpandedWidth: CGFloat = 460

    public static func expandedWidth(forModuleCount count: Int) -> CGFloat {
        let count = max(1, count)
        let cards = CGFloat(count) * moduleCardWidth + CGFloat(count - 1) * moduleSpacing
        return max(minimumExpandedWidth, cards + panelHorizontalPadding * 2)
    }

    /// Height a bar module (Quick Prompt) adds above the cards, so the cards keep their room.
    public static let barHeight: CGFloat = 46
    public static let baseExpandedHeight: CGFloat = 320

    public init(moduleCount: Int, barCount: Int = 0) {
        self.init(
            expandedWidth: Self.expandedWidth(forModuleCount: moduleCount),
            expandedHeight: Self.baseExpandedHeight + CGFloat(max(0, barCount)) * Self.barHeight
        )
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

    /// The notch with an ear on each side, or a small pill at the top center of a display without a notch.
    public var liveFrame: CGRect {
        if let notch = screen.notchRect {
            let ears = notch.insetBy(dx: -metrics.liveEarWidth, dy: 0)
            let width = min(ears.width, availableWidth)
            return CGRect(x: notch.midX - width / 2, y: notch.minY, width: width, height: notch.height)
        }
        return topAnchored(
            width: min(metrics.livePillSize.width, availableWidth),
            height: screen.menuBarHeight > 0 ? screen.menuBarHeight : metrics.livePillSize.height
        )
    }

    /// The notch-height band across the top of the open panel. Scrolling up here closes it; below it the
    /// cards keep their own scrolling.
    public var expandedTopStrip: CGRect {
        let expanded = frame(for: .expanded)
        let height = min(expanded.height, max(screen.topInset, screen.menuBarHeight, 24))
        return CGRect(x: expanded.minX, y: expanded.minY, width: expanded.width, height: height)
    }

    public var expandedPanelWidth: CGFloat {
        min(metrics.expandedWidth, availableWidth)
    }

    public func frame(for state: PanelState, live: Bool = false) -> CGRect {
        switch state {
        case .collapsed:
            return live ? liveFrame : collapsedFrame
        case .expanded:
            return topAnchored(width: expandedPanelWidth, height: metrics.expandedHeight)
        }
    }

    /// The area that keeps a state open. The exit area is deliberately bigger than the entry area so a
    /// pointer that brushes the edge on the way to the menu bar does not make the panel flicker.
    public func hitRect(for state: PanelState, live: Bool = false, slop: CGFloat) -> CGRect {
        frame(for: state, live: live).insetBy(dx: -slop, dy: -slop)
    }

    public func contains(_ point: CGPoint, in state: PanelState, live: Bool = false, slop: CGFloat = 0) -> Bool {
        hitRect(for: state, live: live, slop: slop).contains(point)
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

/// User-tunable open/collapse behaviour plus internal tolerances.
public struct PanelTimings: Equatable, Sendable {
    /// Delay before resting on the notch opens the panel (Settings → hover delay).
    public var hoverDelay: TimeInterval
    /// Delay before collapsing after the pointer leaves (Settings → collapse delay).
    public var collapseDelay: TimeInterval
    /// False means only a click opens the panel; hovering does nothing.
    public var opensOnHover: Bool
    /// Extra room around the expanded panel before it counts as "left".
    public var exitSlop: CGFloat

    public init(
        hoverDelay: TimeInterval = 0.15,
        collapseDelay: TimeInterval = 0.4,
        opensOnHover: Bool = true,
        exitSlop: CGFloat = 12
    ) {
        self.hoverDelay = hoverDelay
        self.collapseDelay = collapseDelay
        self.opensOnHover = opensOnHover
        self.exitSlop = exitSlop
    }
}
