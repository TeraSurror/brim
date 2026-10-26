import XCTest
@testable import BrimKit

/// Lines recorded from Claude Code 2.1.310 (`-p --output-format stream-json --verbose --include-partial-messages`).
@MainActor
final class ClaudeStreamParserTests: XCTestCase {
    func testInitCarriesTheSessionID() {
        let line = #"{"type":"system","subtype":"init","session_id":"0b4d9da7","cwd":"/tmp","model":"claude"}"#
        XCTAssertEqual(ClaudeStreamParser.events(fromLine: line), [.started(sessionID: "0b4d9da7")])
    }

    func testHookLinesAndOtherSystemEventsAreSkipped() {
        let hook = #"{"type":"system","subtype":"hook_started","hook_event":"SessionStart","session_id":"x"}"#
        let rate = #"{"type":"rate_limit_event","rate_limit_info":{},"session_id":"x"}"#
        XCTAssertTrue(ClaudeStreamParser.events(fromLine: hook).isEmpty)
        XCTAssertTrue(ClaudeStreamParser.events(fromLine: rate).isEmpty)
    }

    func testTextDeltasStream() {
        let line = #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"brim ok"}},"session_id":"x"}"#
        XCTAssertEqual(ClaudeStreamParser.events(fromLine: line), [.text("brim ok")])
    }

    func testToolUseStartsAndNewMessagesAreReported() {
        let tool = #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t","name":"Grep","input":{}}}}"#
        let text = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}}"#
        let message = #"{"type":"stream_event","event":{"type":"message_start","message":{}}}"#
        XCTAssertEqual(ClaudeStreamParser.events(fromLine: tool), [.tool("Grep")])
        XCTAssertTrue(ClaudeStreamParser.events(fromLine: text).isEmpty)
        XCTAssertEqual(ClaudeStreamParser.events(fromLine: message), [.turnBreak])
    }

    func testASuccessfulResult() {
        let line = #"{"type":"result","subtype":"success","is_error":false,"result":"brim ok","session_id":"0b4d","total_cost_usd":0.0191}"#
        XCTAssertEqual(
            ClaudeStreamParser.events(fromLine: line),
            [.finished(PromptResult(isError: false, message: "brim ok", sessionID: "0b4d", costUSD: 0.0191))]
        )
    }

    func testAnErrorResult() {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"session_id":"0b4d","errors":["Prompt is too long"]}"#
        guard case .finished(let result)? = ClaudeStreamParser.events(fromLine: line).first else {
            return XCTFail("expected a result")
        }
        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.message, "Prompt is too long")
    }

    func testGarbageIsIgnored() {
        XCTAssertTrue(ClaudeStreamParser.events(fromLine: "not json").isEmpty)
        XCTAssertTrue(ClaudeStreamParser.events(fromLine: "[1,2]").isEmpty)
        XCTAssertTrue(ClaudeStreamParser.events(fromLine: #"{"no":"type"}"#).isEmpty)
    }
}
