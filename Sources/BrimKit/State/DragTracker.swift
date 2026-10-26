/// Notices a content drag (files or text) from global mouse events. A drag that carries content writes to
/// the drag pasteboard, so its change count moves between mouse-down and the first drag event; moving a
/// window or selecting text does not. Only the pasteboard's types are read, never its contents.
public struct DragTracker: Sendable {
    private var baseline: Int?
    /// Non-nil while a content drag is in progress.
    public private(set) var kinds: Set<DropKind>?

    public init() {}

    public mutating func mouseDown(changeCount: Int) {
        baseline = changeCount
        kinds = nil
    }

    /// The drag's kinds once it is known to carry content. `types` is only asked once per drag.
    public mutating func dragged(changeCount: Int, types: () -> Set<DropKind>) -> Set<DropKind>? {
        if kinds == nil, let baseline, changeCount != baseline {
            let found = types()
            kinds = found.isEmpty ? nil : found
            // A drag of something Brim does not understand stays ignored until the next mouse-down.
            if found.isEmpty { self.baseline = nil }
        }
        return kinds
    }

    public mutating func mouseUp() {
        baseline = nil
        kinds = nil
    }
}
