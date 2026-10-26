/// The visible size of a screen's panel. The window frame follows this exactly, which is what makes clicks
/// outside the panel fall through to whatever is below.
public enum PanelState: String, CaseIterable, Equatable, Sendable {
    /// The notch itself (widened when a module has live content), or the slim handle on a display without one.
    case collapsed
    /// The full module panel.
    case expanded
}
