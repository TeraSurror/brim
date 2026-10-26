import Foundation

/// What an integrated agent is doing right now. `waiting` means the agent has stopped and needs the
/// user (a permission prompt, a question or tool approval), so it is the most urgent state in the panel.
public enum AgentStatus: String, Codable, CaseIterable, Sendable {
    case working
    case waiting
    case done
    case error

    public var title: String {
        switch self {
        case .working: "Working"
        case .waiting: "Needs input"
        case .done: "Done"
        case .error: "Failed"
        }
    }

    /// Higher wins when the roster orders sessions and picks the peek's headline.
    var urgency: Int {
        switch self {
        case .waiting: 3
        case .error: 2
        case .working: 1
        case .done: 0
        }
    }
}

/// A validated event from an integration. Initialization fails on purpose: socket and URL input is
/// untrusted, and dropping a malformed event is better than letting it reach the roster.
public struct AgentEvent: Equatable, Sendable {
    public static let maxAgentLength = 64
    public static let maxSessionLength = 128
    public static let maxTitleLength = 200
    public static let maxDetailLength = 300
    public static let maxPathLength = 1024
    public static let maxAppLength = 255
    public static let maxCost = 10_000.0

    public let agentID: String
    public let sessionID: String
    public let status: AgentStatus
    public let title: String?
    public let detail: String?
    public let costUSD: Double?
    public let cwd: String?
    /// Bundle identifier of the app running the session (a terminal or editor). Only ever used to look up
    /// an installed app to bring forward; never executed or opened as a path.
    public let app: String?
    public let timestamp: Date

    public init?(
        agentID: String,
        sessionID: String,
        status: AgentStatus,
        title: String? = nil,
        detail: String? = nil,
        costUSD: Double? = nil,
        cwd: String? = nil,
        app: String? = nil,
        timestamp: Date = Date()
    ) {
        let agent = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !agent.isEmpty, agent.count <= Self.maxAgentLength,
              !session.isEmpty, session.count <= Self.maxSessionLength else { return nil }
        if let costUSD, !costUSD.isFinite || costUSD < 0 || costUSD > Self.maxCost { return nil }

        self.agentID = agent
        self.sessionID = session
        self.status = status
        self.title = Self.clean(title, limit: Self.maxTitleLength)
        self.detail = Self.clean(detail, limit: Self.maxDetailLength)
        self.costUSD = costUSD
        self.cwd = Self.clean(cwd, limit: Self.maxPathLength)
        // An invalid app drops only that field: the status update is still worth showing.
        self.app = Self.bundleIdentifier(app)
        self.timestamp = timestamp
    }

    /// Reverse-DNS characters only, with at least one dot, so the value can name an app and nothing else.
    static func bundleIdentifier(_ value: String?) -> String? {
        guard let value = clean(value, limit: maxAppLength + 1), value.count <= maxAppLength,
              value.contains("."), !value.hasPrefix("."), !value.hasSuffix(".") else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-"))
        guard value.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { return nil }
        return value
    }

    private static func clean(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}

/// One agent session as the panel presents it. `id` is the agent and session together so two tools that
/// happen to use the same session ID never collide.
public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    public let agentID: String
    public let sessionID: String
    public var title: String
    public var detail: String
    public var costUSD: Double?
    public var cwd: String?
    public var app: String?
    public var status: AgentStatus
    public let startedAt: Date
    public var updatedAt: Date

    public var agentName: String { AgentCatalog.displayName(for: agentID) }
    public var displayTitle: String { title.isEmpty ? sessionID : title }
    public var displayDetail: String { detail.isEmpty ? status.title : detail }
    public var openTarget: AgentOpenTarget { AgentOpenTarget(app: app, cwd: cwd) }
    public var costText: String? {
        guard let costUSD else { return nil }
        return String(format: "$%.2f", costUSD)
    }

    public static func key(agentID: String, sessionID: String) -> String {
        "\(agentID)|\(sessionID)"
    }

    init(event: AgentEvent) {
        self.id = Self.key(agentID: event.agentID, sessionID: event.sessionID)
        self.agentID = event.agentID
        self.sessionID = event.sessionID
        self.title = event.title ?? ""
        self.detail = event.detail ?? ""
        self.costUSD = event.costUSD
        self.cwd = event.cwd
        self.app = event.app
        self.status = event.status
        self.startedAt = event.timestamp
        self.updatedAt = event.timestamp
    }

    public func elapsed(now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(startedAt))
    }

    public func elapsedText(now: Date) -> String {
        AgentDuration.text(elapsed(now: now))
    }
}

public enum AgentCatalog {
    /// Friendly names for the tools we document; anything else is shown as the integration named it.
    public static func displayName(for agentID: String) -> String {
        switch agentID.lowercased() {
        case "brim": "Brim"
        case "claude-code", "claude": "Claude Code"
        case "codex": "Codex"
        case "cursor": "Cursor"
        case "vscode", "vs-code": "VS Code"
        default: agentID
        }
    }
}

public enum AgentDuration {
    public static func text(_ interval: TimeInterval) -> String {
        guard interval.isFinite else { return "0s" }
        let seconds = Int(max(0, interval).rounded())
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d"
    }
}

/// One JSON object per socket line. Timestamps are optional so a hook can let Brim use its receive time.
public enum AgentEventDecoder {
    public static let maxLineBytes = 8 * 1024

    private struct WireEvent: Decodable {
        let agent: String
        let session: String
        let status: String
        let title: String?
        let detail: String?
        let costUSD: Double?
        let cwd: String?
        let app: String?
        let timestamp: String?
    }

    public static func decode(line: Data, now: Date = Date()) -> AgentEvent? {
        guard line.count <= maxLineBytes,
              let wire = try? JSONDecoder().decode(WireEvent.self, from: line),
              let status = AgentStatus(rawValue: wire.status.lowercased()) else { return nil }
        return AgentEvent(
            agentID: wire.agent,
            sessionID: wire.session,
            status: status,
            title: wire.title,
            detail: wire.detail,
            costUSD: wire.costUSD,
            cwd: wire.cwd,
            app: wire.app,
            timestamp: AgentTimestamp.parse(wire.timestamp) ?? now
        )
    }
}

enum AgentTimestamp {
    /// Hooks are shell scripts and extensions, so accept both fractional and whole-second ISO 8601.
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
