import XCTest
@testable import BrimKit

final class AgentRosterTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000)

    private func event(
        agent: String = "claude-code",
        session: String = "s1",
        status: AgentStatus = .working,
        title: String? = nil,
        detail: String? = nil,
        cost: Double? = nil,
        at offset: TimeInterval = 0
    ) throws -> AgentEvent {
        try XCTUnwrap(AgentEvent(
            agentID: agent,
            sessionID: session,
            status: status,
            title: title,
            detail: detail,
            costUSD: cost,
            timestamp: base.addingTimeInterval(offset)
        ))
    }

    func testApplyingAnEventCreatesASession() throws {
        var roster = AgentRoster()
        let working = try event(title: "Fix parser", detail: "Running tests", cost: 0.2)

        XCTAssertTrue(roster.apply(working))
        XCTAssertEqual(roster.sessions.count, 1)
        let session = try XCTUnwrap(roster.sessions.first)
        XCTAssertEqual(session.agentName, "Claude Code")
        XCTAssertEqual(session.displayTitle, "Fix parser")
        XCTAssertEqual(session.displayDetail, "Running tests")
        XCTAssertEqual(session.costText, "$0.20")
        XCTAssertEqual(session.startedAt, base)
        XCTAssertEqual(session.updatedAt, base)
    }

    func testRepeatedEventsUpdateTheSameSession() throws {
        var roster = AgentRoster()
        roster.apply(try event(status: .working, title: "Fix parser", detail: "Running tests", cost: 0.2))
        roster.apply(try event(status: .done, detail: "Tests passed", cost: 0.5, at: 10))

        XCTAssertEqual(roster.sessions.count, 1)
        let session = try XCTUnwrap(roster.sessions.first)
        XCTAssertEqual(session.status, .done)
        XCTAssertEqual(session.title, "Fix parser")
        XCTAssertEqual(session.detail, "Tests passed")
        XCTAssertEqual(session.costUSD, 0.5)
        XCTAssertEqual(session.startedAt, base)
        XCTAssertEqual(session.updatedAt, base.addingTimeInterval(10))
    }

    func testTheAppIsKeptUntilAnEventNamesANewOne() throws {
        var roster = AgentRoster()
        roster.apply(try XCTUnwrap(AgentEvent(
            agentID: "claude-code", sessionID: "s1", status: .working, app: "com.apple.Terminal", timestamp: base)))
        roster.apply(try event(status: .waiting, at: 1))
        XCTAssertEqual(roster.sessions.first?.app, "com.apple.Terminal")

        roster.apply(try XCTUnwrap(AgentEvent(
            agentID: "claude-code", sessionID: "s1", status: .working, app: "com.microsoft.VSCode",
            timestamp: base.addingTimeInterval(2))))
        XCTAssertEqual(roster.sessions.first?.app, "com.microsoft.VSCode")
    }

    func testAFinishedEventWithoutDetailClearsStaleProgress() throws {
        var roster = AgentRoster()
        roster.apply(try event(status: .working, detail: "Running tests"))
        roster.apply(try event(status: .error, at: 1))

        XCTAssertEqual(roster.sessions.first?.detail, "")
    }

    func testAStaleEventDoesNotRegressTheSession() throws {
        var roster = AgentRoster()
        roster.apply(try event(status: .working, at: 10))
        XCTAssertFalse(roster.apply(try event(status: .waiting, at: 5)))

        XCTAssertEqual(roster.sessions.first?.status, .working)
        XCTAssertEqual(roster.sessions.first?.updatedAt, base.addingTimeInterval(10))
    }

    func testOrderingPutsWaitingFirstThenFailuresThenWorkingThenDone() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "done", status: .done, at: 4))
        roster.apply(try event(session: "working", status: .working, at: 3))
        roster.apply(try event(session: "error", status: .error, at: 2))
        roster.apply(try event(session: "waiting", status: .waiting, at: 1))

        XCTAssertEqual(roster.sessions.map(\.sessionID), ["waiting", "error", "working", "done"])
    }

    func testNewerSessionsWinWithinTheSameStatus() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "older", status: .working, at: 1))
        roster.apply(try event(session: "newer", status: .working, at: 2))

        XCTAssertEqual(roster.sessions.map(\.sessionID), ["newer", "older"])
    }

    func testPruneRemovesOnlyExpiredFinishedSessions() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "done", status: .done, at: 0))
        roster.apply(try event(session: "error", status: .error, at: 0))
        roster.apply(try event(session: "working", status: .working, at: 0))

        roster.prune(now: base.addingTimeInterval(11 * 60), finishedRetention: 10 * 60)

        XCTAssertEqual(roster.sessions.map(\.sessionID), ["working"])
    }

    func testFinishedSessionsSurviveInsideRetention() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "done", status: .done, at: 0))

        roster.prune(now: base.addingTimeInterval(9 * 60), finishedRetention: 10 * 60)

        XCTAssertEqual(roster.sessions.count, 1)
    }

    func testTheSessionLimitDropsTheLeastUrgentSession() throws {
        var roster = AgentRoster(maxSessions: 2)
        roster.apply(try event(session: "waiting", status: .waiting, at: 1))
        roster.apply(try event(session: "working", status: .working, at: 2))
        roster.apply(try event(session: "done", status: .done, at: 3))

        XCTAssertEqual(roster.sessions.map(\.sessionID), ["waiting", "working"])
    }

    func testClearFinishedKeepsUnfinishedSessions() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "waiting", status: .waiting))
        roster.apply(try event(session: "done", status: .done))
        roster.apply(try event(session: "error", status: .error))

        roster.clearFinished()

        XCTAssertEqual(roster.sessions.map(\.sessionID), ["waiting"])
    }

    func testDismissAndClear() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "one"))
        roster.apply(try event(session: "two"))
        let id = try XCTUnwrap(roster.sessions.first?.id)

        roster.dismiss(id: id)
        XCTAssertEqual(roster.sessions.count, 1)

        roster.clear()
        XCTAssertTrue(roster.sessions.isEmpty)
    }

    func testSummaryCountsAndHeadline() throws {
        var roster = AgentRoster()
        roster.apply(try event(session: "w", status: .working))
        roster.apply(try event(session: "a", status: .waiting))
        roster.apply(try event(session: "e", status: .error))
        roster.apply(try event(session: "d", status: .done))

        let summary = roster.summary
        XCTAssertEqual(summary.waiting, 1)
        XCTAssertEqual(summary.working, 1)
        XCTAssertEqual(summary.errors, 1)
        XCTAssertEqual(summary.done, 1)
        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.finished, 2)
        XCTAssertEqual(summary.headline, .waiting)
        XCTAssertFalse(summary.isIdle)
    }

    func testAnEmptyRosterIsIdle() {
        let summary = AgentRoster().summary
        XCTAssertTrue(summary.isIdle)
        XCTAssertNil(summary.headline)
    }

    func testElapsedTimeUsesTheSuppliedClock() throws {
        var roster = AgentRoster()
        roster.apply(try event(at: 0))
        let session = try XCTUnwrap(roster.sessions.first)

        XCTAssertEqual(session.elapsed(now: base.addingTimeInterval(90)), 90)
        XCTAssertEqual(session.elapsedText(now: base.addingTimeInterval(90)), "1m")
    }

    func testDifferentAgentsWithTheSameSessionIDStaySeparate() throws {
        var roster = AgentRoster()
        roster.apply(try event(agent: "claude-code", session: "shared"))
        roster.apply(try event(agent: "codex", session: "shared"))

        XCTAssertEqual(roster.sessions.count, 2)
        XCTAssertNotEqual(roster.sessions[0].id, roster.sessions[1].id)
    }
}
