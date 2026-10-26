/// A global keyboard shortcut recorded in Settings. `keyCode` is the hardware virtual key code, so the
/// shortcut keeps working when the keyboard layout changes; `keyLabel` is what the key printed when it was
/// recorded and is only used for display.
public struct HotKey: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// Shift alone would swallow ordinary typing, so a global shortcut needs ⌘, ⌥ or ⌃.
    public var isValid: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control])
    }

    /// In the system's order: ⌃⌥⇧⌘.
    public var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel
    }
}

/// What a global shortcut does. One registration per action.
public enum HotKeyAction: String, CaseIterable, Sendable {
    case openPanel
}
