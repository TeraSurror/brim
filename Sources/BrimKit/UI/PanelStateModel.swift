import Combine

/// Per-window bridge between the pure state machine and SwiftUI. Each screen has its own instance.
@MainActor
final class PanelStateModel: ObservableObject {
    /// What the window should draw right now. During a collapse this stays at the previous shape
    /// until the window has retracted, so the panel visibly shrinks into the notch instead of blinking off.
    @Published var state: PanelState
    /// Which layout is visible. Kept separate so the peek can stay on screen while the window grows
    /// into the expanded panel; switching layouts mid-growth is what made the animation look busy.
    @Published var content: PanelState

    init(state: PanelState = .collapsed, content: PanelState = .collapsed) {
        self.state = state
        self.content = content
    }
}
