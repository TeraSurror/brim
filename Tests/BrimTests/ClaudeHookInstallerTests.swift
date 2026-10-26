import XCTest
@testable import BrimKit

@MainActor
final class ClaudeHookInstallerTests: XCTestCase {
    private var home: URL!
    private var installer: ClaudeHookInstaller!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("brim-hook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        installer = ClaudeHookInstaller(home: home, now: { [unowned self] in self.now })
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: home)
    }

    private var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    private var scriptURL: URL { home.appendingPathComponent(".brim/claude-hook.sh") }

    private func writeSettings(_ json: String) throws {
        try Data(json.utf8).write(to: settingsURL)
    }

    private func readSettings() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var backups: [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".claude").path)) ?? []
        return names.filter { $0.hasPrefix("settings.json.brim-backup-") }
    }

    func testMissingClaudeDirectoryIsReportedAndRefused() throws {
        try FileManager.default.removeItem(at: home.appendingPathComponent(".claude"))
        installer.refresh()
        XCTAssertEqual(installer.status, .claudeNotFound)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? ClaudeHookError, .claudeNotFound)
        }
    }

    func testInstallsIntoAFreshClaudeDirectory() throws {
        XCTAssertEqual(installer.status, .notInstalled)

        try installer.install()

        XCTAssertEqual(installer.status, .installed)
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertEqual(script, ClaudeHookConfig.script)
        let mode = try FileManager.default.attributesOfItem(atPath: scriptURL.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o755)
        let commands = ClaudeHookConfig.installedCommands(in: try readSettings())
        XCTAssertEqual(Set(commands.keys), Set(ClaudeHookConfig.hooks.map(\.event)))
        XCTAssertTrue(backups.isEmpty, "Nothing to back up when settings.json did not exist")
    }

    func testInstallKeepsOtherSettingsAndHooksAndBacksUp() throws {
        try writeSettings("""
            {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}
            """)

        try installer.install()

        let settings = try readSettings()
        XCTAssertEqual(settings["model"] as? String, "opus")
        let stop = try XCTUnwrap((settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        XCTAssertTrue(commands.contains("say done"))
        XCTAssertTrue(commands.contains { $0.contains(ClaudeHookConfig.scriptMarker) })
        XCTAssertEqual(backups.count, 1)
    }

    func testInstallingTwiceDoesNotDuplicateHooks() throws {
        try installer.install()
        try installer.install()

        let commands = ClaudeHookConfig.installedCommands(in: try readSettings())
        XCTAssertTrue(commands.values.allSatisfy { $0.count == 1 })
        XCTAssertEqual(installer.status, .installed)
    }

    func testAnOlderHookIsReportedAsOutdatedAndUpdated() throws {
        try writeSettings("""
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\\"$HOME/.brim/claude-hook.sh\\" done 'Finished'"}]}]}}
            """)
        try FileManager.default.createDirectory(
            at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n# old\n".utf8).write(to: scriptURL)
        installer.refresh()
        XCTAssertEqual(installer.status, .outdated)

        try installer.install()

        XCTAssertEqual(installer.status, .installed)
        XCTAssertEqual(try String(contentsOf: scriptURL, encoding: .utf8), ClaudeHookConfig.script)
    }

    func testUnreadableSettingsAreNeverRewritten() throws {
        try writeSettings("{ not json")
        installer.refresh()
        XCTAssertEqual(installer.status, .unreadableSettings)

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? ClaudeHookError, .unreadableSettings)
        }
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptURL.path))
    }

    func testUninstallRemovesOnlyBrimHooksAndTheScript() throws {
        try writeSettings("""
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}
            """)
        try installer.install()

        try installer.uninstall()

        XCTAssertEqual(installer.status, .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptURL.path))
        let settings = try readSettings()
        let hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        XCTAssertEqual(Array(hooks.keys), ["Stop"])
        XCTAssertTrue(ClaudeHookConfig.installedCommands(in: settings).isEmpty)
    }

    func testRemovingDropsEmptyEventsAndTheHooksKey() {
        let merged = ClaudeHookConfig.merging(into: ["theme": "dark"])
        let removed = ClaudeHookConfig.removing(from: merged)
        XCTAssertEqual(removed.keys.sorted(), ["theme"])
    }

    func testTheScriptReportsTheAppAndProjectName() {
        XCTAssertTrue(ClaudeHookConfig.script.contains("__CFBundleIdentifier"))
        XCTAssertTrue(ClaudeHookConfig.script.contains("os.path.basename"))
        XCTAssertTrue(ClaudeHookConfig.script.hasPrefix("#!/bin/sh\n"))
    }
}
