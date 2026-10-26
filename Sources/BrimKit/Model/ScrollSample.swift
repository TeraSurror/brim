import CoreGraphics
import Foundation

/// One scroll event, in CoreGraphics global space. Deltas follow the fingers (or the wheel), whatever the
/// "natural scrolling" setting: positive `deltaY` means fingers moving down, positive `deltaX` right.
public struct ScrollSample: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// A mouse wheel, which has no gesture phases.
        case none
        case began
        case changed
        case ended
    }

    public var location: CGPoint
    public var deltaX: CGFloat
    public var deltaY: CGFloat
    public var phase: Phase
    /// Momentum after the fingers lift. Never acted on, so a fling cannot skip twice.
    public var isMomentum: Bool
    public var timestamp: TimeInterval

    public init(
        location: CGPoint,
        deltaX: CGFloat = 0,
        deltaY: CGFloat = 0,
        phase: Phase,
        isMomentum: Bool = false,
        timestamp: TimeInterval
    ) {
        self.location = location
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.phase = phase
        self.isMomentum = isMomentum
        self.timestamp = timestamp
    }
}

/// What one scroll gesture amounts to, decided once per gesture.
public enum ScrollGesture: Equatable, Sendable {
    case down
    case up
    case left
    case right
}
