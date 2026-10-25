/// The visible size of a screen's panel. The window frame follows this exactly, which is what makes clicks
/// outside the panel fall through to whatever is below.
public enum PanelState: String, CaseIterable, Equatable, Sendable {
    /// The notch itself, or the slim handle on a display without one.
    case collapsed
    /// A short strip that confirms the notch is alive.
    case peek
    /// The full module panel.
    case expanded
}
