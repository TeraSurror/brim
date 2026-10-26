import XCTest
@testable import BrimKit

final class AgentNotificationTrackerTests: XCTestCase {
    private let tracker = AgentNotificationTracker()
    private let base = Date(timeIntervalSince1970: 1_000)

    private func session(
        status: AgentStatus = .waiting,
        title: String = "Fix the parser",
        detail: String = "Waiting for permission",
        cwd: String? = "/tmp/project"
    ) throws -> AgentSession {
        let event = try XCTUnwrap(AgentEvent(
            agentID: "claude-code",
            sessionID: "s1",
            status: status,
            title: title,
            detail: detail,
            cwd: cwd,
            timestamp: base
        ))
        return AgentSession(event: event)
    }

    func testNewWaitingSessionNotifies() throws {
        let note = tracker.notification(
            for: try session(),
            previousStatus: .working,
            panelActive: false
        )

        XCTAssertEqual(note?.title, "Claude Code needs your input")
        XCTAssertEqual(note?.body, "Fix the parser — Waiting for permission")
        XCTAssertEqual(note?.target.cwd, "/tmp/project")
        XCTAssertEqual(note?.sessionID, "claude-code|s1")
    }

    func testRepeatedWaitingDoesNotNotifyAgain() throws {
        let note = tracker.notification(
            for: try session(),
            previousStatus: .waiting,
            panelActive: false
        )

        XCTAssertNil(note)
    }

    func testAnOpenPanelSuppressesTheNotification() throws {
        let note = tracker.notification(
            for: try session(),
            previousStatus: .working,
            panelActive: true
        )

        XCTAssertNil(note)
    }

    func testWorkThenWaitingNotifiesAgain() throws {
        XCTAssertNotNil(tracker.notification(
            for: try session(),
            previousStatus: .working,
            panelActive: false
        ))
        XCTAssertNil(tracker.notification(
            for: try session(status: .working),
            previousStatus: .waiting,
            panelActive: false
        ))
        XCTAssertNotNil(tracker.notification(
            for: try session(),
            previousStatus: .working,
            panelActive: false
        ))
    }

    func testDoneDoesNotNotify() throws {
        XCTAssertNil(tracker.notification(
            for: try session(status: .done),
            previousStatus: .working,
            panelActive: false
        ))
    }

    func testFailureNotifies() throws {
        let note = tracker.notification(
            for: try session(status: .error, detail: "Tests failed"),
            previousStatus: .working,
            panelActive: false
        )

        XCTAssertEqual(note?.title, "Claude Code failed")
        XCTAssertEqual(note?.body, "Fix the parser — Tests failed")
    }

    func testANewSessionWithNoPreviousStatusCanNotify() throws {
        XCTAssertNotNil(tracker.notification(
            for: try session(),
            previousStatus: nil,
            panelActive: false
        ))
    }

    func testBodyIsTruncatedAndNilCwdIsPreserved() throws {
        let note = tracker.notification(
            for: try session(detail: String(repeating: "x", count: 400), cwd: nil),
            previousStatus: .working,
            panelActive: false
        )

        XCTAssertEqual(note?.body.count, 180)
        XCTAssertNil(note?.target.cwd)
    }

    func testEmptyDetailUsesTheTitle() throws {
        let note = tracker.notification(
            for: try session(detail: ""),
            previousStatus: .working,
            panelActive: false
        )

        XCTAssertEqual(note?.body, "Fix the parser")
    }
}
