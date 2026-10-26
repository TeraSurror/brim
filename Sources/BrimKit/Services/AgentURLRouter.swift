import Foundation

public enum AgentCommand: Equatable, Sendable {
    case event(AgentEvent)
    case dismiss(agentID: String, sessionID: String)
    case clear
}

/// Parses the `brim://agent` URLs that simple hooks and editor extensions open. Kept pure so the URL
/// contract can be tested without going through NSApplication.
public enum AgentURLRouter {
    public static func command(from url: URL, now: Date = Date()) -> AgentCommand? {
        guard url.scheme?.lowercased() == "brim",
              url.host?.lowercased() == "agent",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            values[item.name.lowercased()] = item.value ?? ""
        }

        switch (values["action"] ?? "").lowercased() {
        case "clear":
            return .clear
        case "dismiss":
            guard let agent = values["agent"], let session = values["session"],
                  !agent.isEmpty, agent.count <= AgentEvent.maxAgentLength,
                  !session.isEmpty, session.count <= AgentEvent.maxSessionLength else { return nil }
            return .dismiss(agentID: agent, sessionID: session)
        default:
            guard let agent = values["agent"], let session = values["session"],
                  let rawStatus = values["status"],
                  let status = AgentStatus(rawValue: rawStatus.lowercased()) else { return nil }
            let event = AgentEvent(
                agentID: agent,
                sessionID: session,
                status: status,
                title: values["title"],
                detail: values["detail"],
                costUSD: values["cost"].flatMap(Double.init),
                cwd: values["cwd"],
                app: values["app"],
                timestamp: AgentTimestamp.parse(values["timestamp"]) ?? now
            )
            return event.map(AgentCommand.event)
        }
    }
}
