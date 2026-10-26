import Foundation

/// One run of the user's `claude` CLI. The prompt goes to standard input, never through a shell.
public struct PromptRequest: Equatable, Sendable {
    public var prompt: String
    /// The working directory; Claude Code's read-only tools are limited to it and `extraDirectories`.
    public var folder: URL
    /// Continues an earlier conversation from the same panel.
    public var resumeSessionID: String?
    /// Folders of attached files, readable for this run only (F20).
    public var extraDirectories: [URL]

    public init(prompt: String, folder: URL, resumeSessionID: String? = nil, extraDirectories: [URL] = []) {
        self.prompt = prompt
        self.folder = folder
        self.resumeSessionID = resumeSessionID
        self.extraDirectories = extraDirectories
    }
}

/// What a run reports while it streams.
public enum PromptEvent: Equatable, Sendable {
    case started(sessionID: String)
    case text(String)
    /// A read-only tool started, such as "Read" or "Grep".
    case tool(String)
    /// A new assistant message began after a tool call.
    case turnBreak
    case finished(PromptResult)
}

public struct PromptResult: Equatable, Sendable {
    public var isError: Bool
    /// The final answer, or a short, readable error.
    public var message: String
    public var sessionID: String?
    public var costUSD: Double?

    public init(isError: Bool, message: String, sessionID: String? = nil, costUSD: Double? = nil) {
        self.isError = isError
        self.message = message
        self.sessionID = sessionID
        self.costUSD = costUSD
    }
}

/// One exchange in the panel's conversation.
public struct PromptTurn: Identifiable, Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running
        case done
        case failed(String)
        case stopped
    }

    public let id: UUID
    public var prompt: String
    public var answer: String
    /// The tool currently running, shown as a status line while the answer has not started.
    public var activeTool: String?
    public var state: State
    public var costUSD: Double?

    public init(id: UUID = UUID(), prompt: String, answer: String = "", state: State = .running) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
        self.state = state
    }
}
