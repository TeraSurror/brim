import Foundation

/// Counts per state, plus the state that deserves the peek's headline.
public struct AgentSummary: Equatable, Sendable {
    public var waiting: Int
    public var working: Int
    public var errors: Int
    public var done: Int

    public init(waiting: Int = 0, working: Int = 0, errors: Int = 0, done: Int = 0) {
        self.waiting = waiting
        self.working = working
        self.errors = errors
        self.done = done
    }

    public var total: Int { waiting + working + errors + done }
    public var finished: Int { errors + done }
    public var isIdle: Bool { total == 0 }

    public var headline: AgentStatus? {
        if waiting > 0 { return .waiting }
        if errors > 0 { return .error }
        if working > 0 { return .working }
        if done > 0 { return .done }
        return nil
    }
}

/// Pure session aggregation: events in, ordered sessions out. It owns no timer and no I/O, so the panel's
/// urgency rules are testable with plain values and a supplied clock.
public struct AgentRoster: Equatable, Sendable {
    public static let defaultMaxSessions = 8

    public private(set) var sessions: [AgentSession] = []
    public let maxSessions: Int

    public init(maxSessions: Int = defaultMaxSessions) {
        self.maxSessions = max(1, maxSessions)
    }

    /// Returns false when the event is older than the session it would update. Late events must not make a
    /// finished session look busy again.
    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Bool {
        let key = AgentSession.key(agentID: event.agentID, sessionID: event.sessionID)
        if let index = sessions.firstIndex(where: { $0.id == key }) {
            guard event.timestamp >= sessions[index].updatedAt else { return false }
            var session = sessions[index]
            session.status = event.status
            if let title = event.title { session.title = title }
            if event.status == .done || event.status == .error {
                // A finished event without a detail should not leave "Running tests" behind.
                session.detail = event.detail ?? ""
            } else if let detail = event.detail {
                session.detail = detail
            }
            if let cost = event.costUSD { session.costUSD = cost }
            if let cwd = event.cwd { session.cwd = cwd }
            if let app = event.app { session.app = app }
            session.updatedAt = event.timestamp
            sessions[index] = session
        } else {
            sessions.append(AgentSession(event: event))
        }
        sort()
        trimToLimit()
        return true
    }

    public mutating func dismiss(id: String) {
        sessions.removeAll { $0.id == id }
    }

    public mutating func clear() {
        sessions.removeAll()
    }

    /// "Finished" includes failures so the card can be cleared in one action; failures stay visible until
    /// they are cleared or expire.
    public mutating func clearFinished() {
        sessions.removeAll { $0.status == .done || $0.status == .error }
    }

    /// Working and waiting sessions are never expired automatically: a long tool run should not become a
    /// false failure just because it has not emitted an event for a while.
    public mutating func prune(now: Date, finishedRetention: TimeInterval) {
        guard finishedRetention.isFinite else { return }
        let cutoff = now.addingTimeInterval(-max(0, finishedRetention))
        sessions.removeAll { session in
            guard session.status == .done || session.status == .error else { return false }
            return session.updatedAt <= cutoff
        }
    }

    public var summary: AgentSummary {
        var summary = AgentSummary()
        for session in sessions {
            switch session.status {
            case .waiting: summary.waiting += 1
            case .working: summary.working += 1
            case .error: summary.errors += 1
            case .done: summary.done += 1
            }
        }
        return summary
    }

    private mutating func sort() {
        sessions.sort { lhs, rhs in
            if lhs.status.urgency != rhs.status.urgency {
                return lhs.status.urgency > rhs.status.urgency
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }

    private mutating func trimToLimit() {
        guard sessions.count > maxSessions else { return }
        sessions.removeLast(sessions.count - maxSessions)
    }
}
