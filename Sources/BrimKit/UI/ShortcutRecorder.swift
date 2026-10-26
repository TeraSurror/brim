import AppKit
import SwiftUI

/// Records a global shortcut in Settings. While recording, the next key press with ⌘, ⌥ or ⌃ becomes the
/// shortcut; Esc cancels. The registered shortcut is paused meanwhile (see `AppModel.isRecordingShortcut`).
struct ShortcutRecorder: View {
    let shortcut: HotKey?
    @Binding var isRecording: Bool
    let onRecord: (HotKey) -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording.toggle()
            } label: {
                Text(title)
                    .monospacedDigit()
                    .frame(minWidth: 120)
            }
            .background(
                KeyCaptureView(
                    isActive: isRecording,
                    onKey: { hotKey in
                        isRecording = false
                        onRecord(hotKey)
                    },
                    onCancel: { isRecording = false }
                )
            )
            .accessibilityLabel(isRecording ? "Recording shortcut. Press keys, or Escape to cancel." : "Shortcut")
            .accessibilityValue(shortcut?.displayString ?? "None")

            if shortcut != nil, !isRecording {
                Button("Clear", action: onClear)
                    .accessibilityLabel("Clear shortcut")
            }
        }
    }

    private var title: String {
        if isRecording { return "Type a shortcut…" }
        return shortcut?.displayString ?? "Record Shortcut"
    }
}

/// Becomes first responder while recording so it sees key presses, including ⌘ combinations that would
/// otherwise be treated as menu key equivalents.
private struct KeyCaptureView: NSViewRepresentable {
    let isActive: Bool
    let onKey: (HotKey) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        CaptureView()
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onKey = onKey
        view.onCancel = onCancel
        view.isActive = isActive
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if isActive, window.firstResponder !== view {
                window.makeFirstResponder(view)
            } else if !isActive, window.firstResponder === view {
                window.makeFirstResponder(nil)
            }
        }
    }

    final class CaptureView: NSView {
        var isActive = false
        var onKey: ((HotKey) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { isActive }

        override func keyDown(with event: NSEvent) {
            guard isActive else { return super.keyDown(with: event) }
            capture(event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isActive, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            capture(event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            if isActive { onCancel?() }
            return super.resignFirstResponder()
        }

        private func capture(_ event: NSEvent) {
            let modifiers = Self.modifiers(from: event.modifierFlags)
            if event.keyCode == 53, modifiers.isEmpty {
                onCancel?()
                return
            }
            let hotKey = HotKey(keyCode: event.keyCode, modifiers: modifiers, keyLabel: Self.label(for: event))
            guard hotKey.isValid else {
                NSSound.beep()
                return
            }
            onKey?(hotKey)
        }

        private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotKey.Modifiers {
            var modifiers: HotKey.Modifiers = []
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            if flags.contains(.command) { modifiers.insert(.command) }
            return modifiers
        }

        private static let specialKeys: [UInt16: String] = [
            49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]

        private static func label(for event: NSEvent) -> String {
            if let special = specialKeys[event.keyCode] { return special }
            let characters = event.charactersIgnoringModifiers?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return characters.isEmpty ? "Key \(event.keyCode)" : characters.uppercased()
        }
    }
}
