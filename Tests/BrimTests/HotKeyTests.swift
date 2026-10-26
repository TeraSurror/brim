import XCTest
@testable import BrimKit

@MainActor
final class HotKeyTests: XCTestCase {
    func testDisplayStringUsesTheSystemModifierOrder() {
        let hotKey = HotKey(keyCode: 49, modifiers: [.command, .shift, .option, .control], keyLabel: "Space")
        XCTAssertEqual(hotKey.displayString, "⌃⌥⇧⌘Space")
    }

    func testAShortcutNeedsCommandOptionOrControl() {
        XCTAssertFalse(HotKey(keyCode: 0, modifiers: [], keyLabel: "A").isValid)
        XCTAssertFalse(HotKey(keyCode: 0, modifiers: [.shift], keyLabel: "A").isValid)
        XCTAssertTrue(HotKey(keyCode: 0, modifiers: [.control], keyLabel: "A").isValid)
        XCTAssertTrue(HotKey(keyCode: 0, modifiers: [.option, .shift], keyLabel: "A").isValid)
        XCTAssertTrue(HotKey(keyCode: 0, modifiers: [.command], keyLabel: "A").isValid)
    }
}
