/// How much a module's live content deserves the notch. Only the highest priority is shown at a time.
public enum LiveActivityPriority: Int, Comparable, Sendable {
    /// Background progress, such as an agent that is working.
    case ambient = 0
    /// Something the user started and may glance at, such as playing media.
    case media = 1
    /// Something that needs the user, such as an agent waiting for input or failing.
    case attention = 2

    public static func < (lhs: LiveActivityPriority, rhs: LiveActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A module's request to show content beside the notch while the panel is closed. The module draws the
/// content itself through `BrimModule.liveView(_:)`; the shell only decides who wins and how big the ears are.
public struct LiveActivity: Equatable, Sendable {
    public var priority: LiveActivityPriority

    public init(priority: LiveActivityPriority) {
        self.priority = priority
    }
}

/// The two ears of the live notch: left and right of the hardware notch.
public enum LiveActivityEdge: Sendable {
    case leading
    case trailing
}
