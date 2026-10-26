import XCTest
@testable import BrimKit

@MainActor
final class ClaudeCLITests: XCTestCase {
    func testArgumentsAreReadOnlyAndNeverCarryThePrompt() {
        let request = PromptRequest(prompt: "--delete everything", folder: URL(fileURLWithPath: "/tmp/project"))
        let arguments = ClaudeCLIRunner.arguments(for: request)

        XCTAssertEqual(arguments.first, "-p")
        XCTAssertFalse(arguments.contains("--delete everything"))
        let tools = arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] }
        XCTAssertEqual(tools, "Read,Grep,Glob")
        XCTAssertTrue(arguments.contains("--strict-mcp-config"))
        XCTAssertFalse(arguments.contains("--resume"))
        XCTAssertFalse(arguments.contains { $0.contains("bypass") || $0.contains("dangerously") })
        XCTAssertEqual(Array(arguments.drop { $0 != "--output-format" }.prefix(2)), ["--output-format", "stream-json"])
    }

    func testFollowUpsResumeAndAttachmentsAddDirectories() {
        let request = PromptRequest(
            prompt: "and?",
            folder: URL(fileURLWithPath: "/tmp/project"),
            resumeSessionID: "abc",
            extraDirectories: [URL(fileURLWithPath: "/tmp/a"), URL(fileURLWithPath: "/tmp/b")]
        )
        let arguments = ClaudeCLIRunner.arguments(for: request)
        XCTAssertEqual(Array(arguments.drop { $0 != "--resume" }.prefix(2)), ["--resume", "abc"])
        XCTAssertEqual(arguments.filter { $0 == "--add-dir" }.count, 2)
        XCTAssertTrue(arguments.contains("/tmp/a"))
        XCTAssertTrue(arguments.contains("/tmp/b"))
    }

    func testEnvironmentFindsNodeAndMarksTheRun() {
        let environment = ClaudeCLIRunner.environment(
            base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/me"],
            executable: URL(fileURLWithPath: "/Users/me/.npm-global/bin/claude")
        )
        XCTAssertEqual(environment["BRIM_QUICK_PROMPT"], "1")
        XCTAssertEqual(environment["HOME"], "/Users/me")
        XCTAssertTrue(environment["PATH"]?.hasPrefix("/Users/me/.npm-global/bin:") == true)
        XCTAssertTrue(environment["PATH"]?.hasSuffix("/usr/bin:/bin") == true)
    }

    func testFailureMessagesAreReadable() {
        XCTAssertTrue(ClaudeCLIRunner.failureMessage(exitCode: 1, stderr: "Invalid API key · Please run /login")
            .contains("isn't logged in"))
        XCTAssertEqual(ClaudeCLIRunner.failureMessage(exitCode: 2, stderr: ""), "Claude Code exited with code 2.")
        XCTAssertEqual(
            ClaudeCLIRunner.failureMessage(exitCode: 3, stderr: "boom\nstack"),
            "Claude Code exited with code 3: boom"
        )
    }

    func testTheLocatorPicksTheFirstExecutableCandidate() {
        let home = NSHomeDirectory()
        let found = ClaudeCLILocator.firstExecutable(in: ["~/.local/bin/claude", "/opt/homebrew/bin/claude"]) {
            $0 == "/opt/homebrew/bin/claude" || $0 == "\(home)/.local/bin/claude"
        }
        XCTAssertEqual(found, "\(home)/.local/bin/claude")
        XCTAssertNil(ClaudeCLILocator.firstExecutable(in: ["/nope/claude"]) { _ in false })
    }

    func testTheHookSkipsQuickPromptRuns() {
        XCTAssertTrue(ClaudeHookConfig.script.contains(#"[ -n "$BRIM_QUICK_PROMPT" ] && exit 0"#))
        XCTAssertTrue(ClaudeHookConfig.script.contains("brim-hook-version: 3"))
    }
}
