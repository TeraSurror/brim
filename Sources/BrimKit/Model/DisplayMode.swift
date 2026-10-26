/// Which displays show Brim (Settings → General → Show Brim on).
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case all
    case notchedOnly
    /// The display with the menu bar in System Settings → Displays.
    case mainOnly

    public var title: String {
        switch self {
        case .all: return "All displays"
        case .notchedOnly: return "Only the notched display"
        case .mainOnly: return "Only the main display"
        }
    }

    /// The screens that get a panel, in the order given. `screens.first` is the main display, as with
    /// `NSScreen.screens`. With the lid closed there is no notch, so "notched only" falls back to the main
    /// display rather than leaving Brim with nowhere to appear.
    public func screens(in screens: [ScreenInfo]) -> [ScreenInfo] {
        switch self {
        case .all:
            return screens
        case .notchedOnly:
            let notched = screens.filter(\.hasNotch)
            return notched.isEmpty ? Array(screens.prefix(1)) : notched
        case .mainOnly:
            return Array(screens.prefix(1))
        }
    }
}
