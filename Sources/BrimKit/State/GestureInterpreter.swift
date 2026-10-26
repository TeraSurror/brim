import CoreGraphics
import Foundation

/// Turns a stream of scroll events into at most one gesture per trackpad swipe or wheel step. Pure, so the
/// thresholds and the momentum rule are unit tested.
public struct GestureInterpreter: Sendable {
    /// Points of finger travel before a vertical swipe counts. Small, because opening should feel instant.
    public static let verticalThreshold: CGFloat = 8
    /// Horizontal swipes skip tracks, so they need a deliberate distance.
    public static let horizontalThreshold: CGFloat = 24
    /// The winning axis must lead the other by this factor, so a diagonal drift does nothing.
    public static let dominance: CGFloat = 1.5
    /// Mouse wheels have no phases; one action per this interval keeps a free-spinning wheel from repeating.
    public static let wheelCooldown: TimeInterval = 0.4

    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var origin: CGPoint?
    private var fired = false
    private var lastWheelAction: TimeInterval?

    public init() {}

    /// The gesture and the point where it started, once the gesture is decided.
    public mutating func feed(_ sample: ScrollSample) -> (gesture: ScrollGesture, location: CGPoint)? {
        guard !sample.isMomentum else { return nil }

        switch sample.phase {
        case .none:
            return wheel(sample)
        case .began:
            reset()
            origin = sample.location
            return accumulate(sample)
        case .changed:
            if origin == nil { origin = sample.location }
            return accumulate(sample)
        case .ended:
            reset()
            return nil
        }
    }

    private mutating func accumulate(_ sample: ScrollSample) -> (gesture: ScrollGesture, location: CGPoint)? {
        guard !fired else { return nil }
        accumulatedX += sample.deltaX
        accumulatedY += sample.deltaY
        guard let gesture = Self.gesture(
            x: accumulatedX,
            y: accumulatedY,
            vertical: Self.verticalThreshold,
            horizontal: Self.horizontalThreshold
        ) else { return nil }
        fired = true
        return (gesture, origin ?? sample.location)
    }

    private mutating func wheel(_ sample: ScrollSample) -> (gesture: ScrollGesture, location: CGPoint)? {
        if let last = lastWheelAction, sample.timestamp - last < Self.wheelCooldown { return nil }
        guard let gesture = Self.gesture(x: sample.deltaX, y: sample.deltaY, vertical: 0, horizontal: 0) else {
            return nil
        }
        lastWheelAction = sample.timestamp
        return (gesture, sample.location)
    }

    private mutating func reset() {
        accumulatedX = 0
        accumulatedY = 0
        origin = nil
        fired = false
    }

    private static func gesture(x: CGFloat, y: CGFloat, vertical: CGFloat, horizontal: CGFloat) -> ScrollGesture? {
        if abs(y) > vertical, abs(y) >= abs(x) * dominance {
            return y > 0 ? .down : .up
        }
        if abs(x) > horizontal, abs(x) >= abs(y) * dominance {
            return x > 0 ? .right : .left
        }
        return nil
    }
}
