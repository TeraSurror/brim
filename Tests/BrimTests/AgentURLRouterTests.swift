import XCTest
@testable import BrimKit

final class AgentURLRouterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func command(_ string: String) -> AgentCommand? {
        guard let url = URL(string: string) else {
            XCTFail("Not a URL: \(string)")
            return nil
        }
        return AgentURLRouter.command(from: url, now: now)
    }

    func testParsesAnEventURL() throws {
        let result = try XCTUnwrap(command(
            "brim://agent?agent=claude-code&session=abc&status=waiting&title=Fix%20the%20parser&detail=Tool%20use&cost=0.42&cwd=%2Ftmp%2Fproject"
        ))
        guard case .event(let event) = result else {
            return XCTFail("Expected an event, got \(result)")
        }

        XCTAssertEqual(event.agentID, "claude-code")
        XCTAssertEqual(event.sessionID, "abc")
        XCTAssertEqual(event.status, .waiting)
        XCTAssertEqual(event.title, "Fix the parser")
        XCTAssertEqual(event.detail, "Tool use")
        XCTAssertEqual(event.costUSD, 0.42)
        XCTAssertEqual(event.cwd, "/tmp/project")
        XCTAssertEqual(event.timestamp, now)
    }

    func testStatusIsCaseInsensitive() throws {
        let result = try XCTUnwrap(command("brim://agent?agent=codex&session=s&status=WORKING"))
        guard case .event(let event) = result else {
            return XCTFail("Expected an event")
        }
        XCTAssertEqual(event.status, .working)
    }

    func testTimestampIsParsed() throws {
        let result = try XCTUnwrap(command(
            "brim://agent?agent=codex&session=s&status=done&timestamp=2026-10-25T21%3A00%3A00Z"
        ))
        guard case .event(let event) = result else {
            return XCTFail("Expected an event")
        }
        XCTAssertEqual(event.timestamp, try XCTUnwrap(AgentTimestamp.parse("2026-10-25T21:00:00Z")))
    }

    func testDismissAndClear() {
        XCTAssertEqual(
            command("brim://agent?action=dismiss&agent=claude-code&session=abc"),
            .dismiss(agentID: "claude-code", sessionID: "abc")
        )
        XCTAssertEqual(command("brim://agent?action=CLEAR"), .clear)
    }

    func testRejectsWrongSchemeOrHost() {
        XCTAssertNil(command("https://agent?agent=a&session=s&status=working"))
        XCTAssertNil(command("brim://other?agent=a&session=s&status=working"))
    }

    func testRejectsMissingOrInvalidFields() {
        XCTAssertNil(command("brim://agent?agent=a&status=working"))
        XCTAssertNil(command("brim://agent?session=s&status=working"))
        XCTAssertNil(command("brim://agent?agent=a&session=s"))
        XCTAssertNil(command("brim://agent?agent=a&session=s&status=running"))
        XCTAssertNil(command("brim://agent?agent=&session=s&status=working"))
        XCTAssertNil(command("brim://agent?action=dismiss&agent=a"))
    }

    func testInvalidCostIsTreatedAsAbsent() throws {
        let result = try XCTUnwrap(command("brim://agent?agent=a&session=s&status=working&cost=not-a-number"))
        guard case .event(let event) = result else {
            return XCTFail("Expected an event")
        }
        XCTAssertNil(event.costUSD)
    }

    func testEncodedAmpersandStaysInTheTitle() throws {
        let result = try XCTUnwrap(command(
            "brim://agent?agent=a&session=s&status=working&title=Tom%20%26%20Jerry"
        ))
        guard case .event(let event) = result else {
            return XCTFail("Expected an event")
        }
        XCTAssertEqual(event.title, "Tom & Jerry")
    }
}
