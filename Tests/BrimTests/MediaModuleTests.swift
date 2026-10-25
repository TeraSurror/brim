import XCTest
@testable import BrimKit

@MainActor
final class MediaModuleTests: XCTestCase {
    private var service: FakeNowPlayingService!
    private var scheduler: FakeScheduler!
    private var module: MediaModule!

    override func setUp() async throws {
        service = FakeNowPlayingService()
        service.sources = [.spotify, .music]
        scheduler = FakeScheduler()
        module = MediaModule(service: service, scheduler: scheduler)
    }

    private func track(title: String = "Track", source: NowPlayingSource = .spotify) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: "Artist",
            duration: 200,
            elapsed: 10,
            isPlaying: true,
            source: source
        )
    }

    func testEnablingWhileThePanelIsClosedDoesNotStartMonitoring() {
        module.setEnabled(true)
        XCTAssertEqual(service.startCount, 0)

        module.setPanelActive(true)
        XCTAssertEqual(service.startCount, 1)
    }

    func testOpeningBeforeEnablingStartsWhenTheModuleIsTurnedOn() {
        module.setPanelActive(true)
        XCTAssertEqual(service.startCount, 0)

        module.setEnabled(true)
        XCTAssertEqual(service.startCount, 1)
    }

    func testCollapseStopsMonitoringAfterTheGracePeriod() {
        module.setEnabled(true)
        module.setPanelActive(true)

        module.setPanelActive(false)
        scheduler.advance(by: 0.9)
        XCTAssertEqual(service.stopCount, 0)

        scheduler.advance(by: 0.1)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testReopeningCancelsTheScheduledStop() {
        module.setEnabled(true)
        module.setPanelActive(true)
        module.setPanelActive(false)
        scheduler.advance(by: 0.5)

        module.setPanelActive(true)
        scheduler.advance(by: 2)

        XCTAssertEqual(service.stopCount, 0)
        XCTAssertEqual(service.startCount, 1)
    }

    func testDisablingStopsImmediately() {
        module.setEnabled(true)
        module.setPanelActive(true)
        module.setEnabled(false)

        XCTAssertEqual(service.stopCount, 1)
        XCTAssertNil(module.nowPlaying)
    }

    func testServiceUpdatesReachTheModule() {
        let nowPlaying = track(title: "Updated")
        service.emit(nowPlaying)

        XCTAssertEqual(module.nowPlaying, nowPlaying)
    }

    func testPreferredPlayerIsForwardedToTheService() {
        module.applyPreferredPlayer(ScriptablePlayer.music.rawValue)

        XCTAssertEqual(service.followed, [ScriptablePlayer.music.rawValue])
        XCTAssertEqual(module.preferredSourceID, ScriptablePlayer.music.rawValue)
    }

    func testChoosingAPlayerGoesThroughTheHost() {
        var choices: [String?] = []
        module.onPreferredPlayerChange = { choices.append($0) }

        module.choosePlayer(nil)
        module.choosePlayer(ScriptablePlayer.spotify.rawValue)

        XCTAssertEqual(choices.count, 2)
        XCTAssertNil(choices[0])
        XCTAssertEqual(choices[1], ScriptablePlayer.spotify.rawValue)
        XCTAssertTrue(service.followed.isEmpty)
    }

    func testChoosingWithoutAHostAppliesLocally() {
        module.choosePlayer(ScriptablePlayer.music.rawValue)
        XCTAssertEqual(service.followed, [ScriptablePlayer.music.rawValue])
    }

    func testCommandsAndSeeksAreForwarded() {
        module.send(.next)
        module.seek(to: 42)

        XCTAssertEqual(service.commands, [.next])
        XCTAssertEqual(service.seeks, [42])
    }

    func testModuleAsksForAutomationWithAnExplanation() {
        XCTAssertEqual(module.requiredPermissions, [.automation])
        XCTAssertFalse(module.permissionExplanation.isEmpty)
        XCTAssertTrue(module.permissionExplanation.contains("Automation"))
    }

    func testSourcesFollowTheService() {
        XCTAssertEqual(module.sources.map(\.id), [ScriptablePlayer.spotify.rawValue,
                                                  ScriptablePlayer.music.rawValue])

        service.sources = [.music]
        service.onSourcesChange?([.music])
        XCTAssertEqual(module.sources, [.music])
    }
}
