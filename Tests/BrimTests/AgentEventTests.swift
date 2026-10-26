import XCTest
@testable import BrimKit

final class AgentEventTests: XCTestCase {
    func testValidEventTrimsAndClampsText() throws {
        let event = try XCTUnwrap(AgentEvent(
            agentID: "  claude-code  ",
            sessionID: "  session-1  ",
            status: .working,
            title: "  Fix the parser  ",
            detail: "  Running tests  ",
            costUSD: 0.42,
            cwd: "/tmp/project"
        ))

        XCTAssertEqual(event.agentID, "claude-code")
        XCTAssertEqual(event.sessionID, "session-1")
        XCTAssertEqual(event.status, .working)
        XCTAssertEqual(event.title, "Fix the parser")
        XCTAssertEqual(event.detail, "Running tests")
        XCTAssertEqual(event.costUSD, 0.42)
        XCTAssertEqual(event.cwd, "/tmp/project")
    }

    func testLongTextIsTruncated() throws {
        let event = try XCTUnwrap(AgentEvent(
            agentID: "codex",
            sessionID: "s",
            status: .working,
            title: String(repeating: "a", count: 250),
            detail: String(repeating: "b", count: 350)
        ))

        XCTAssertEqual(event.title?.count, AgentEvent.maxTitleLength)
        XCTAssertEqual(event.detail?.count, AgentEvent.maxDetailLength)
    }

    func testInvalidIdentityOrCostIsRejected() {
        XCTAssertNil(AgentEvent(agentID: "", sessionID: "s", status: .working))
        XCTAssertNil(AgentEvent(agentID: "   ", sessionID: "s", status: .working))
        XCTAssertNil(AgentEvent(agentID: "a", sessionID: "", status: .working))
        XCTAssertNil(AgentEvent(
            agentID: String(repeating: "a", count: AgentEvent.maxAgentLength + 1),
            sessionID: "s",
            status: .working
        ))
        XCTAssertNil(AgentEvent(agentID: "a", sessionID: "s", status: .working, costUSD: -1))
        XCTAssertNil(AgentEvent(agentID: "a", sessionID: "s", status: .working, costUSD: .infinity))
        XCTAssertNil(AgentEvent(
            agentID: "a",
            sessionID: "s",
            status: .working,
            costUSD: AgentEvent.maxCost + 1
        ))
    }

    func testDecodesAJsonLine() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let line = Data("""
        {"agent":"claude-code","session":"abc","status":"WAITING","title":"Approve?","detail":"Tool use","costUSD":0.5,"cwd":"/tmp","timestamp":"2026-10-25T21:00:00Z"}
        """.utf8)

        let event = try XCTUnwrap(AgentEventDecoder.decode(line: line, now: now))

        XCTAssertEqual(event.agentID, "claude-code")
        XCTAssertEqual(event.sessionID, "abc")
        XCTAssertEqual(event.status, .waiting)
        XCTAssertEqual(event.title, "Approve?")
        XCTAssertEqual(event.detail, "Tool use")
        XCTAssertEqual(event.costUSD, 0.5)
        XCTAssertEqual(event.cwd, "/tmp")
        XCTAssertEqual(event.timestamp, try XCTUnwrap(AgentTimestamp.parse("2026-10-25T21:00:00Z")))
    }

    func testMissingTimestampFallsBackToReceiveTime() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let line = Data(#"{"agent":"codex","session":"s","status":"working"}"#.utf8)
        let event = try XCTUnwrap(AgentEventDecoder.decode(line: line, now: now))
        XCTAssertEqual(event.timestamp, now)
    }

    func testMalformedEventsAreRejected() {
        XCTAssertNil(AgentEventDecoder.decode(line: Data("not json".utf8)))
        XCTAssertNil(AgentEventDecoder.decode(line: Data(#"{"agent":"a","session":"s","status":"running"}"#.utf8)))
        XCTAssertNil(AgentEventDecoder.decode(line: Data(#"{"agent":"a","status":"working"}"#.utf8)))
        XCTAssertNil(AgentEventDecoder.decode(line: Data(repeating: 0x20, count: AgentEventDecoder.maxLineBytes + 1)))
    }

    func testTimestampAcceptsFractionalSeconds() throws {
        let base = try XCTUnwrap(AgentTimestamp.parse("2026-10-25T21:00:00Z"))
        let fractional = try XCTUnwrap(AgentTimestamp.parse("2026-10-25T21:00:00.500Z"))
        XCTAssertEqual(fractional.timeIntervalSince(base), 0.5, accuracy: 0.001)
    }

    func testDurationFormatting() {
        XCTAssertEqual(AgentDuration.text(0), "0s")
        XCTAssertEqual(AgentDuration.text(12), "12s")
        XCTAssertEqual(AgentDuration.text(90), "1m")
        XCTAssertEqual(AgentDuration.text(3_900), "1h 5m")
        XCTAssertEqual(AgentDuration.text(90_000), "1d")
    }

    func testCatalogNamesKnownTools() {
        XCTAssertEqual(AgentCatalog.displayName(for: "claude-code"), "Claude Code")
        XCTAssertEqual(AgentCatalog.displayName(for: "claude"), "Claude Code")
        XCTAssertEqual(AgentCatalog.displayName(for: "codex"), "Codex")
        XCTAssertEqual(AgentCatalog.displayName(for: "cursor"), "Cursor")
        XCTAssertEqual(AgentCatalog.displayName(for: "vscode"), "VS Code")
        XCTAssertEqual(AgentCatalog.displayName(for: "custom-tool"), "custom-tool")
    }
}
