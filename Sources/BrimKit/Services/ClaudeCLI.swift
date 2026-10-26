import Foundation

/// Finds `claude` in the usual install folders, then on the login shell's `PATH`. Apps opened from Finder
/// get a minimal `PATH`, so the shell is asked once, off the main thread, and the answer is cached.
@MainActor
public final class ClaudeCLILocator: ClaudeCLILocating {
    public static let candidates = [
        "~/.local/bin/claude",
        "~/.claude/local/claude",
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        "~/.npm-global/bin/claude",
        "~/.bun/bin/claude",
        "~/.volta/bin/claude",
    ]

    private var shellResult: URL?
    private var askedShell = false

    public init() {}

    public func locate(override: String?) -> URL? {
        if let override, !override.isEmpty {
            let path = Self.expand(override)
            return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if let found = Self.firstExecutable(in: Self.candidates, isExecutable: FileManager.default.isExecutableFile) {
            return URL(fileURLWithPath: found)
        }
        askLoginShellOnce()
        return shellResult
    }

    /// Pure, for tests: the first candidate that exists and is executable, with `~` expanded.
    public static func firstExecutable(in candidates: [String], isExecutable: (String) -> Bool) -> String? {
        candidates.map(expand).first(where: isExecutable)
    }

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    private func askLoginShellOnce() {
        guard !askedShell else { return }
        askedShell = true
        Task.detached(priority: .utility) {
            let found = Self.loginShellLookup()
            await MainActor.run { [weak self] in self?.shellResult = found }
        }
    }

    /// Runs `command -v claude` in the user's login shell with a short timeout. Only the shell is executed;
    /// the path it prints is checked before Brim would ever run it.
    nonisolated private static func loginShellLookup() -> URL? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v claude"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(3)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Runs `claude -p` as a child process: the prompt on standard input, stream-json on standard output.
@MainActor
public final class ClaudeCLIRunner: PromptRunning {
    /// Standard error kept for the error message; the rest goes to the log.
    nonisolated private static let stderrLimit = 8 * 1024

    public init() {}

    /// Read-only and self-contained: only Read, Grep and Glob exist for the run, and no MCP server is loaded,
    /// so a one-line prompt from the notch cannot edit files, run commands or reach the network through tools.
    public static func arguments(for request: PromptRequest) -> [String] {
        var arguments = [
            "-p",
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--tools", "Read,Grep,Glob",
            "--strict-mcp-config",
        ]
        if let session = request.resumeSessionID {
            arguments += ["--resume", session]
        }
        for directory in request.extraDirectories {
            arguments += ["--add-dir", directory.path]
        }
        return arguments
    }

    /// Finder-launched apps lack the user's `PATH`; npm installs of `claude` need `node` next to it.
    public static func environment(base: [String: String], executable: URL) -> [String: String] {
        var environment = base
        let extra = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin"]
        let path = (extra + [base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
        environment["PATH"] = path
        // Brim's own Claude Code hook skips runs that carry this, so quick prompts don't show as agent sessions.
        environment["BRIM_QUICK_PROMPT"] = "1"
        return environment
    }

    /// A short, readable message for a run that ended without a result line.
    public static func failureMessage(exitCode: Int32, stderr: String) -> String {
        let lower = stderr.lowercased()
        if lower.contains("log in") || lower.contains("login") || lower.contains("authenticat") {
            return "Claude Code isn't logged in. Run claude in Terminal once to log in, then try again."
        }
        if lower.contains("no conversation found") || lower.contains("session") && lower.contains("not found") {
            return "That conversation can't be continued. Start a new one."
        }
        let firstLine = stderr.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty
            ? "Claude Code exited with code \(exitCode)."
            : "Claude Code exited with code \(exitCode): \(firstLine.prefix(200))"
    }

    public func run(
        _ request: PromptRequest,
        executable: URL,
        onEvent: @escaping @MainActor (PromptEvent) -> Void
    ) -> TaskHandle {
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(for: request)
        process.currentDirectoryURL = request.folder
        process.environment = Self.environment(base: ProcessInfo.processInfo.environment, executable: executable)

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let state = RunState()
        output.fileHandleForReading.readabilityHandler = { handle in
            let lines = state.appendOutput(handle.availableData)
            guard !lines.isEmpty else { return }
            Task { @MainActor in
                for line in lines {
                    for event in ClaudeStreamParser.events(fromLine: line) {
                        if case .finished = event { state.markFinished() }
                        onEvent(event)
                    }
                }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            state.appendError(handle.availableData, limit: Self.stderrLimit)
        }
        process.terminationHandler = { process in
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            let remaining = state.appendOutput(output.fileHandleForReading.readDataToEndOfFile(), flush: true)
            let code = process.terminationStatus
            let reason = process.terminationReason
            Task { @MainActor in
                for line in remaining {
                    for event in ClaudeStreamParser.events(fromLine: line) {
                        if case .finished = event { state.markFinished() }
                        onEvent(event)
                    }
                }
                guard !state.isFinished else { return }
                let stderr = state.errorText
                if !stderr.isEmpty { Log.agent.error("Quick prompt stderr: \(stderr, privacy: .public)") }
                let message = state.wasStopped || reason == .uncaughtSignal
                    ? "Stopped."
                    : Self.failureMessage(exitCode: code, stderr: stderr)
                onEvent(.finished(PromptResult(isError: !state.wasStopped, message: message)))
            }
        }

        do {
            try process.run()
        } catch {
            Log.agent.error("Quick prompt could not start: \(error.localizedDescription, privacy: .public)")
            onEvent(.finished(PromptResult(isError: true, message: "Brim couldn't run \(executable.path).")))
            return TaskHandle()
        }
        input.fileHandleForWriting.write(Data(request.prompt.utf8))
        try? input.fileHandleForWriting.close()
        Log.agent.info("Quick prompt started in \(request.folder.path, privacy: .public)")

        return TaskHandle {
            guard process.isRunning else { return }
            state.markStopped()
            process.interrupt()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Byte buffering shared by the pipe handlers, which run on background queues.
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var errorData = Data()
    private var finished = false
    private var stopped = false

    func appendOutput(_ data: Data, flush: Bool = false) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        if flush, !buffer.isEmpty {
            lines.append(String(decoding: buffer, as: UTF8.self))
            buffer.removeAll()
        }
        return lines.filter { !$0.isEmpty }
    }

    func appendError(_ data: Data, limit: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard errorData.count < limit else { return }
        errorData.append(data.prefix(limit - errorData.count))
    }

    var errorText: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func markFinished() { lock.lock(); finished = true; lock.unlock() }
    func markStopped() { lock.lock(); stopped = true; lock.unlock() }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    var wasStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}
