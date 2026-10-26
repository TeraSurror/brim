import Foundation

public enum ClaudeHookStatus: Equatable, Sendable {
    /// `~/.claude` does not exist, so Claude Code has never run for this user.
    case claudeNotFound
    case notInstalled
    /// Some of Brim's hooks or an older script are present; installing again updates them.
    case outdated
    case installed
    /// `~/.claude/settings.json` is not valid JSON. Brim never rewrites a file it cannot parse.
    case unreadableSettings
}

public enum ClaudeHookError: LocalizedError, Equatable {
    case claudeNotFound
    case unreadableSettings
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            "Claude Code hasn't been run on this Mac yet (~/.claude is missing)."
        case .unreadableSettings:
            "~/.claude/settings.json isn't valid JSON, so Brim left it alone. Fix it, then try again."
        case .writeFailed(let message):
            "Brim couldn't update the Claude Code settings: \(message)"
        }
    }
}

/// What Brim adds to Claude Code: the hook script and one hook per lifecycle event. Kept as pure functions
/// over the decoded settings object so the merge can be tested without touching a real home directory.
public enum ClaudeHookConfig {
    /// Brim recognises its own hooks by this path, so other hooks in the same events are never touched.
    public static let scriptMarker = ".brim/claude-hook.sh"
    public static let scriptCommand = "\"$HOME/.brim/claude-hook.sh\""

    public struct Hook: Equatable, Sendable {
        public let event: String
        public let matcher: String?
        public let status: AgentStatus
        public let detail: String

        public var command: String { "\(scriptCommand) \(status.rawValue) '\(detail)'" }
    }

    public static let hooks: [Hook] = [
        Hook(event: "SessionStart", matcher: nil, status: .working, detail: "Session started"),
        Hook(event: "UserPromptSubmit", matcher: nil, status: .working, detail: "Working on your prompt"),
        Hook(event: "PreToolUse", matcher: "*", status: .working, detail: "Running a tool"),
        Hook(
            event: "Notification",
            matcher: "permission_prompt|idle_prompt|agent_needs_input",
            status: .waiting,
            detail: "Waiting for your input"
        ),
        Hook(event: "Stop", matcher: nil, status: .done, detail: "Finished"),
        Hook(event: "SessionEnd", matcher: nil, status: .done, detail: "Session ended"),
    ]

    /// Reads Claude Code's hook JSON from stdin and writes one event line to Brim's socket. It never fails
    /// the hook: if Brim is not running the event is dropped. `__CFBundleIdentifier` is set by macOS for
    /// processes started from an app, so it names the terminal or editor running Claude Code.
    public static let script = #"""
        #!/bin/sh
        # brim-hook-version: 2
        # Installed by Brim (Settings → Agents). Reports Claude Code activity to Brim's local socket.
        # usage: claude-hook.sh <working|waiting|done|error> [detail]  (hook JSON arrives on stdin)
        /usr/bin/python3 -c '
        import json, os, socket, sys, time
        status = sys.argv[1] if len(sys.argv) > 1 else "working"
        detail = sys.argv[2] if len(sys.argv) > 2 else ""
        try:
            hook = json.load(sys.stdin)
        except Exception:
            hook = {}
        cwd = str(hook.get("cwd") or os.getcwd())
        tool = hook.get("tool_name")
        if status == "working" and tool:
            detail = "Running " + str(tool)
        event = {
            "agent": "claude-code",
            "session": str(hook.get("session_id") or "unknown"),
            "status": status,
            "title": os.path.basename(cwd.rstrip("/")) or "Claude Code",
            "detail": detail,
            "cwd": cwd,
            "app": os.environ.get("__CFBundleIdentifier", ""),
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        path = os.path.expanduser("~/Library/Application Support/Brim/agent.sock")
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.settimeout(0.5)
            client.connect(path)
            client.sendall((json.dumps(event) + "\n").encode())
            client.close()
        except OSError:
            pass
        ' "${1:-working}" "${2:-}"
        exit 0

        """#

    private static func isBrimHook(_ hook: Any) -> Bool {
        ((hook as? [String: Any])?["command"] as? String)?.contains(scriptMarker) == true
    }

    /// Settings with every Brim hook removed. Groups and events left empty are dropped; everything else is
    /// kept as it was.
    public static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var events = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in events {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let hooks = group["hooks"] as? [Any] else { return group }
                let remaining = hooks.filter { !isBrimHook($0) }
                if remaining.isEmpty { return nil }
                var copy = group
                copy["hooks"] = remaining
                return copy
            }
            events[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = events.isEmpty ? nil : events
        return settings
    }

    /// Settings with exactly Brim's current hooks, replacing any older Brim entries.
    public static func merging(into settings: [String: Any]) -> [String: Any] {
        var settings = removing(from: settings)
        var events = settings["hooks"] as? [String: Any] ?? [:]
        for hook in hooks {
            var groups = events[hook.event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [["type": "command", "command": hook.command]]]
            if let matcher = hook.matcher { group["matcher"] = matcher }
            groups.append(group)
            events[hook.event] = groups
        }
        settings["hooks"] = events
        return settings
    }

    /// Brim commands present in the settings, by event, to compare against `hooks`.
    public static func installedCommands(in settings: [String: Any]) -> [String: [String]] {
        guard let events = settings["hooks"] as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (event, value) in events {
            for group in value as? [[String: Any]] ?? [] {
                for hook in group["hooks"] as? [Any] ?? [] where isBrimHook(hook) {
                    if let command = (hook as? [String: Any])?["command"] as? String {
                        result[event, default: []].append(command)
                    }
                }
            }
        }
        return result
    }

    public static func status(settings: [String: Any], script: String?) -> ClaudeHookStatus {
        let installed = installedCommands(in: settings)
        if installed.isEmpty && script == nil { return .notInstalled }
        let expected = Dictionary(grouping: hooks, by: \.event).mapValues { $0.map(\.command) }
        return installed == expected && script == Self.script ? .installed : .outdated
    }
}

/// Installs Brim's Claude Code hook into a home directory. Every write of `settings.json` is preceded by a
/// timestamped backup next to it, and a file that is not valid JSON is never rewritten.
@MainActor
public final class ClaudeHookInstaller: ClaudeHookInstalling {
    public private(set) var status: ClaudeHookStatus = .notInstalled

    private let home: URL
    private let now: () -> Date
    private let fileManager = FileManager.default

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: @escaping () -> Date = Date.init
    ) {
        self.home = home
        self.now = now
        refresh()
    }

    private var claudeDirectory: URL { home.appendingPathComponent(".claude", isDirectory: true) }
    private var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    private var scriptURL: URL { home.appendingPathComponent(ClaudeHookConfig.scriptMarker) }

    public func refresh() {
        guard fileManager.fileExists(atPath: claudeDirectory.path) else {
            status = .claudeNotFound
            return
        }
        guard let settings = try? readSettings() else {
            status = .unreadableSettings
            return
        }
        let script = try? String(contentsOf: scriptURL, encoding: .utf8)
        status = ClaudeHookConfig.status(settings: settings, script: script)
    }

    public func install() throws {
        defer { refresh() }
        guard fileManager.fileExists(atPath: claudeDirectory.path) else { throw ClaudeHookError.claudeNotFound }
        guard let settings = try? readSettings() else { throw ClaudeHookError.unreadableSettings }
        do {
            try writeScript()
            try writeSettings(ClaudeHookConfig.merging(into: settings))
            Log.agent.info("Installed the Claude Code hook")
        } catch {
            throw ClaudeHookError.writeFailed(error.localizedDescription)
        }
    }

    public func uninstall() throws {
        defer { refresh() }
        guard fileManager.fileExists(atPath: claudeDirectory.path) else { throw ClaudeHookError.claudeNotFound }
        guard let settings = try? readSettings() else { throw ClaudeHookError.unreadableSettings }
        do {
            if !ClaudeHookConfig.installedCommands(in: settings).isEmpty {
                try writeSettings(ClaudeHookConfig.removing(from: settings))
            }
            if fileManager.fileExists(atPath: scriptURL.path) {
                try fileManager.removeItem(at: scriptURL)
            }
            Log.agent.info("Removed the Claude Code hook")
        } catch {
            throw ClaudeHookError.writeFailed(error.localizedDescription)
        }
    }

    /// A missing file is an empty settings object; an unparsable one throws.
    private func readSettings() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeHookError.unreadableSettings
        }
        return object
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        if fileManager.fileExists(atPath: settingsURL.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let backup = claudeDirectory.appendingPathComponent(
                "settings.json.brim-backup-\(formatter.string(from: now()))")
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
            try fileManager.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }

    private func writeScript() throws {
        let directory = scriptURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try Data(ClaudeHookConfig.script.utf8).write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }
}
