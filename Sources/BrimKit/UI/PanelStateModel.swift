import Combine

/// Per-window bridge between the pure state machine and SwiftUI. Each screen has its own instance.
@MainActor
final class PanelStateModel: ObservableObject {
    @Published var state: PanelState

    init(state: PanelState = .collapsed) {
        self.state = state
    }
}
