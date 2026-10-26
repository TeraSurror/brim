import XCTest
@testable import BrimKit

@MainActor
final class MarkdownBlocksTests: XCTestCase {
    func testParagraphsHeadingsAndLists() {
        let blocks = MarkdownBlocks.parse("""
            ## Summary
            First line
            continues here.

            - one **bold**
            * two
            1. first
            2) second
            """)
        XCTAssertEqual(blocks, [
            .heading(level: 2, text: "Summary"),
            .paragraph("First line\ncontinues here."),
            .bullet("one **bold**"),
            .bullet("two"),
            .numbered(number: 1, text: "first"),
            .numbered(number: 2, text: "second"),
        ])
    }

    func testCodeFencesKeepTheirTextVerbatim() {
        let blocks = MarkdownBlocks.parse("Run:\n```swift\nlet a = 1\n\n- not a list\n```\nDone")
        XCTAssertEqual(blocks, [
            .paragraph("Run:"),
            .code(language: "swift", text: "let a = 1\n\n- not a list"),
            .paragraph("Done"),
        ])
    }

    func testAnUnfinishedFenceStillRendersAsCodeWhileStreaming() {
        XCTAssertEqual(MarkdownBlocks.parse("```\nlet a"), [.code(language: "", text: "let a")])
    }

    func testHashWithoutASpaceIsNotAHeading() {
        XCTAssertEqual(MarkdownBlocks.parse("#hashtag"), [.paragraph("#hashtag")])
    }
}
