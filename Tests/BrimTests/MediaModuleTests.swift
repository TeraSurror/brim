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

    func testEnablingTheModuleNeedsNoPermission() {
        // Automation is optional and only asked for when the user follows Spotify or Music.
        XCTAssertTrue(module.requiredPermissions.isEmpty)
    }

    // MARK: - Live notch

    private func paused(_ nowPlaying: NowPlaying) -> NowPlaying {
        var copy = nowPlaying
        copy.isPlaying = false
        return copy
    }

    func testLiveNotchKeepsTheHelperRunningWithThePanelClosed() {
        module.setEnabled(true)
        module.setLiveActivityEnabled(true)
        XCTAssertEqual(service.startCount, 1)

        module.setPanelActive(true)
        module.setPanelActive(false)
        scheduler.advance(by: 5)
        XCTAssertEqual(service.stopCount, 0)
    }

    func testTurningTheLiveNotchOffStopsAfterTheGraceWhenNoPanelIsOpen() {
        module.setEnabled(true)
        module.setLiveActivityEnabled(true)
        module.setLiveActivityEnabled(false)
        scheduler.advance(by: 1)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testDisablingStopsEvenWithTheLiveNotchOn() {
        module.setEnabled(true)
        module.setLiveActivityEnabled(true)
        module.setEnabled(false)
        XCTAssertEqual(service.stopCount, 1)
    }

    func testPlayingMediaPublishesALiveActivity() {
        var published: [LiveActivity?] = []
        let subscription = module.liveActivityPublisher.sink { published.append($0) }
        defer { subscription.cancel() }

        module.setEnabled(true)
        module.setLiveActivityEnabled(true)
        service.emit(track())

        XCTAssertEqual(module.liveActivity, LiveActivity(priority: .media))
        XCTAssertEqual(published.last, LiveActivity(priority: .media))
    }

    func testPausingHidesTheLiveNotchOnlyAfterTheGracePeriod() {
        module.setEnabled(true)
        module.setLiveActivityEnabled(true)
        let playing = track()
        service.emit(playing)
        service.emit(paused(playing))

        scheduler.advance(by: MediaModule.liveGracePeriod - 0.1)
        XCTAssertNotNil(module.liveActivity)
        scheduler.advance(by: 0.1)
        XCTAssertNil(module.liveActivity)
    }

    func testResumingWithinTheGraceKeepsTheLiveNotch() {
        module.setEnabled(true)
        module.setLiveActivityEnabled(true)
        let playing = track()
        service.emit(playing)
        service.emit(nil)
        scheduler.advance(by: 1)
        service.emit(track(title: "Next"))
        scheduler.advance(by: 10)

        XCTAssertNotNil(module.liveActivity)
    }

    func testNoLiveActivityWhenTheSettingIsOffOrTheModuleIsDisabled() {
        module.setEnabled(true)
        service.emit(track())
        XCTAssertNil(module.liveActivity)

        module.setLiveActivityEnabled(true)
        XCTAssertNotNil(module.liveActivity)

        module.setEnabled(false)
        XCTAssertNil(module.liveActivity)
    }

    func testPanelVisibilityIsForwardedForThePollCadence() {
        module.setPanelActive(true)
        module.setPanelActive(false)
        XCTAssertEqual(service.panelVisibility, [true, false])
    }

    func testSourcesFollowTheService() {
        XCTAssertEqual(module.sources.map(\.id), [ScriptablePlayer.spotify.rawValue,
                                                  ScriptablePlayer.music.rawValue])

        service.sources = [.music]
        service.onSourcesChange?([.music])
        XCTAssertEqual(module.sources, [.music])
    }
}
