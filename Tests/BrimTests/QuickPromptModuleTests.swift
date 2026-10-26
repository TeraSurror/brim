import Combine
import XCTest
@testable import BrimKit

@MainActor
final class QuickPromptModuleTests: XCTestCase {
    private var runner: FakePromptRunner!
    private var locator: FakeCLILocator!
    private var scratch: URL!
    private var project: URL!
    private var module: QuickPromptModule!

    override func setUp() async throws {
        runner = FakePromptRunner()
        locator = FakeCLILocator()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        scratch = base.appendingPathComponent("scratch")
        project = base.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        module = QuickPromptModule(runner: runner, locator: locator, scratchDirectory: scratch)
        module.setEnabled(true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: scratch.deletingLastPathComponent())
    }

    private func ask(_ prompt: String) {
        module.draft = prompt
        module.send()
    }

    func testItSitsAboveTheCardsAndExplainsItselfFirst() {
        XCTAssertEqual(module.placement, .bar)
        XCTAssertTrue(module.explainsBeforeEnabling)
        XCTAssertTrue(module.requiredPermissions.isEmpty)
    }

    func testAnswersStreamIntoTheTurn() {
        ask("  What is Brim?  ")
        XCTAssertEqual(runner.requests.first?.prompt, "What is Brim?")
        XCTAssertEqual(module.draft, "")
        XCTAssertTrue(module.isShowingConversation)
        XCTAssertTrue(module.isRunning)

        runner.emit(.started(sessionID: "s1"))
        runner.emit(.tool("Read"))
        XCTAssertEqual(module.turns.last?.activeTool, "Read")
        runner.emit(.text("A notch "))
        runner.emit(.text("panel."))
        runner.finish("A notch panel.", session: "s1", cost: 0.02)

        let turn = module.turns.last
        XCTAssertEqual(turn?.answer, "A notch panel.")
        XCTAssertEqual(turn?.state, .done)
        XCTAssertNil(turn?.activeTool)
        XCTAssertEqual(turn?.costUSD, 0.02)
        XCTAssertFalse(module.isRunning)
    }

    func testANewMessageAfterAToolStartsANewParagraph() {
        ask("Look")
        runner.emit(.text("Checking."))
        runner.emit(.turnBreak)
        runner.emit(.text("Found it."))
        XCTAssertEqual(module.turns.last?.answer, "Checking.\n\nFound it.")
    }

    func testFollowUpsContinueTheSessionAndNewStartsOver() {
        ask("One")
        runner.emit(.started(sessionID: "s1"))
        runner.finish("1", session: "s1")
        ask("Two")
        XCTAssertEqual(runner.requests.last?.resumeSessionID, "s1")

        runner.finish("2", session: "s1")
        module.startNewConversation()
        XCTAssertTrue(module.turns.isEmpty)
        XCTAssertFalse(module.isShowingConversation)
        ask("Three")
        XCTAssertNil(runner.requests.last?.resumeSessionID)
    }

    func testOnlyOnePromptRunsAtATime() {
        ask("One")
        ask("Two")
        XCTAssertEqual(runner.requests.count, 1)
        XCTAssertEqual(module.draft, "Two")
    }

    func testStopEndsTheRun() {
        ask("Long")
        module.stop()
        XCTAssertEqual(runner.cancelCount, 1)
        XCTAssertEqual(module.turns.last?.state, .stopped)
        XCTAssertFalse(module.isRunning)
    }

    func testErrorsAreShownOnTheTurn() {
        ask("Hi")
        runner.emit(.finished(PromptResult(isError: true, message: "Claude Code isn't logged in.")))
        XCTAssertEqual(module.turns.last?.state, .failed("Claude Code isn't logged in."))
    }

    func testAMissingCLIFailsWithoutRunningAnything() {
        locator.found = nil
        ask("Hi")
        XCTAssertTrue(runner.requests.isEmpty)
        guard case .failed(let message)? = module.turns.last?.state else { return XCTFail("expected a failure") }
        XCTAssertTrue(message.contains("can't find the claude command"))
    }

    func testTheCLIOverrideIsUsed() {
        module.applyCLIPath("/custom/claude")
        ask("Hi")
        XCTAssertEqual(runner.executables.last?.path, "/custom/claude")
        XCTAssertEqual(locator.overrides.last, "/custom/claude")
    }

    func testNothingRunsWhileDisabledOrEmpty() {
        ask("   ")
        module.setEnabled(false)
        ask("Hi")
        XCTAssertTrue(runner.requests.isEmpty)
    }

    func testWithoutAFolderItRunsInTheScratchFolder() {
        ask("Hi")
        XCTAssertEqual(runner.requests.last?.folder, scratch)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: scratch.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testOpeningThePanelDefaultsToTheMostRecentAgentProject() {
        module.defaultFolderPath = { [project] in project?.path }
        module.setPanelActive(true)
        XCTAssertEqual(module.folder, .folder(project.standardizedFileURL))
        ask("Hi")
        XCTAssertEqual(runner.requests.last?.folder.standardizedFileURL, project.standardizedFileURL)
    }

    func testAMissingDefaultFolderFallsBackToScratch() {
        module.defaultFolderPath = { "/does/not/exist" }
        module.setPanelActive(true)
        XCTAssertEqual(module.folder, .scratch)
    }

    func testAChosenFolderIsKeptAndRemembered() {
        var saved: [[String]] = []
        module.onRecentFoldersChange = { saved.append($0) }
        module.defaultFolderPath = { "/tmp" }

        module.choose(.folder(project))
        module.setPanelActive(true)

        XCTAssertEqual(module.folder, .folder(project))
        XCTAssertEqual(saved.last, [project.path])
    }

    func testChangingFolderMidConversationStartsANewOne() {
        ask("One")
        runner.finish("1", session: "s1")
        module.choose(.folder(project))
        XCTAssertTrue(module.turns.isEmpty)
        ask("Two")
        XCTAssertNil(runner.requests.last?.resumeSessionID)
    }

    func testRecentFoldersAreCappedAndSkipMissingOnes() {
        let paths = (0..<8).map { index -> String in
            let url = project.appendingPathComponent("p\(index)")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.path
        }
        module.applyRecentFolders(["/missing"] + paths)
        XCTAssertEqual(module.recentFolders.count, QuickPromptModule.maxRecentFolders)
        XCTAssertEqual(module.recentFolders.first?.path, paths[0])
    }

    func testTheNotchShowsAWorkingGlyphThenTheUnreadOutcome() {
        XCTAssertNil(module.liveActivity)
        ask("Hi")
        XCTAssertEqual(module.liveActivity, LiveActivity(priority: .ambient))
        XCTAssertEqual(module.liveState, .running)

        runner.finish("Done")
        XCTAssertEqual(module.liveActivity, LiveActivity(priority: .ambient))
        XCTAssertEqual(module.liveState, .done)

        module.setPanelActive(true)
        XCTAssertNil(module.liveActivity)
        XCTAssertNil(module.liveState)
    }

    func testAnAnswerReadWithThePanelOpenLeavesTheNotchBare() {
        module.setPanelActive(true)
        ask("Hi")
        runner.finish("Done")
        XCTAssertNil(module.liveActivity)
    }

    func testTheConversationTakesOverThePanelUntilDone() {
        var fills: [Bool] = []
        let subscription = module.fillsPanelPublisher.sink { fills.append($0) }
        defer { subscription.cancel() }

        ask("Hi")
        module.closeConversation()
        module.showConversation()
        XCTAssertEqual(fills, [false, true, false, true])
    }

    func testDisablingStopsARunningPrompt() {
        ask("Hi")
        module.setEnabled(false)
        XCTAssertEqual(runner.cancelCount, 1)
        XCTAssertTrue(module.turns.isEmpty)
        XCTAssertNil(module.liveActivity)
    }
}
