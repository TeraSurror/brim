import SwiftUI

/// Lets a view inside the panel ask for keyboard focus (F16: the prompt field is the one click that may
/// take it) and learn when the panel has it, without touching the window.
struct PanelFocus {
    var isFocused = false
    var request: () -> Void = {}
}

private struct PanelFocusKey: EnvironmentKey {
    static let defaultValue = PanelFocus()
}

extension EnvironmentValues {
    var panelFocus: PanelFocus {
        get { self[PanelFocusKey.self] }
        set { self[PanelFocusKey.self] = newValue }
    }
}
