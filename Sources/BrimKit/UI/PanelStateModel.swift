import Combine

/// Per-window bridge between the pure state machine and SwiftUI. Each screen has its own instance.
@MainActor
final class PanelStateModel: ObservableObject {
    /// What the window should draw right now. During a collapse this stays `.expanded` until the window has
    /// retracted, so the panel visibly shrinks into the notch instead of blinking off.
    @Published var state: PanelState
    /// Whether the expanded layout is visible. Kept separate so the content can fade in once the window is
    /// nearly grown; switching layouts mid-growth is what made the animation look busy.
    @Published var content: PanelState
    /// The black live-notch shape. It stays up while the ears retract so they do not vanish before the window.
    @Published var showsLiveShape: Bool
    /// The module's ear views inside the live shape.
    @Published var showsLiveContent: Bool

    init(
        state: PanelState = .collapsed,
        content: PanelState = .collapsed,
        showsLiveShape: Bool = false,
        showsLiveContent: Bool = false
    ) {
        self.state = state
        self.content = content
        self.showsLiveShape = showsLiveShape
        self.showsLiveContent = showsLiveContent
    }
}
