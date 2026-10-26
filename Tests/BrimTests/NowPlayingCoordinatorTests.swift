import XCTest
@testable import BrimKit

@MainActor
final class NowPlayingCoordinatorTests: XCTestCase {
    private var adapter: FakeMediaAdapter!
    private var automation: FakePlayerAutomation!
    private var discovery: FakePlayerDiscovery!
    private var scheduler: FakeScheduler!
    private var coordinator: NowPlayingCoordinator!

    override func setUp() async throws {
        adapter = FakeMediaAdapter()
        automation = FakePlayerAutomation()
        discovery = FakePlayerDiscovery()
        scheduler = FakeScheduler()
        coordinator = NowPlayingCoordinator(
            adapter: adapter,
            automation: automation,
            discovery: discovery,
            scheduler: scheduler
        )
    }

    private func track(
        _ source: NowPlayingSource,
        title: String = "Track",
        artwork: Bool = false
    ) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: "Artist",
            duration: 200,
            elapsed: 10,
            isPlaying: true,
            source: source,
            artwork: artwork ? NowPlayingArtwork(data: Data("cover".utf8)) : nil
        )
    }

    func testAutomaticFollowsTheAdapter() {
        coordinator.startMonitoring()
        coordinator.follow(nil)
        adapter.emit(track(.spotify))

        XCTAssertEqual(coordinator.current?.source, .spotify)
        XCTAssertEqual(coordinator.current?.title, "Track")
    }

    func testPreferredPlayerWinsOverTheAdapter() {
        coordinator.startMonitoring()
        automation.snapshots[.music] = track(.music, title: "From Music")
        automation.snapshots[.spotify] = track(.spotify, title: "From Spotify")

        coordinator.follow(ScriptablePlayer.music.rawValue)
        adapter.emit(track(.spotify, title: "System track"))

        XCTAssertEqual(coordinator.current?.title, "From Music")
        XCTAssertEqual(coordinator.current?.source, .music)
    }

    func testAdapterWinsWhenItAlreadyReportsThePreferredPlayer() {
        coordinator.startMonitoring()
        coordinator.follow(ScriptablePlayer.music.rawValue)
        automation.snapshots[.music] = track(.music, title: "No artwork")
        let adapterTrack = track(.music, title: "With artwork", artwork: true)
        adapter.emit(adapterTrack)

        XCTAssertEqual(coordinator.current, adapterTrack)
    }

    func testFallsBackToTheAdapterWhenThePreferredPlayerStops() {
        coordinator.startMonitoring()
        automation.snapshots[.music] = track(.music, title: "From Music")
        coordinator.follow(ScriptablePlayer.music.rawValue)
        XCTAssertEqual(coordinator.current?.title, "From Music")

        automation.snapshots[.music] = nil
        adapter.emit(track(.spotify, title: "From Spotify"))
        // The panel is closed, so the followed player is polled every three seconds.
        scheduler.advance(by: 3)

        XCTAssertEqual(coordinator.current?.title, "From Spotify")
    }

    func testPreferredPlayerIsPolledOncePerSecondWithThePanelOpen() {
        coordinator.startMonitoring()
        coordinator.follow(ScriptablePlayer.music.rawValue)
        coordinator.setPanelVisible(true)
        // Opening the panel reads right away instead of waiting out the slow cadence.
        XCTAssertEqual(automation.reads.count, 2)
        automation.resetReads()

        scheduler.advance(by: 0.5)
        XCTAssertEqual(automation.reads.count, 0)

        scheduler.advance(by: 0.5)
        XCTAssertEqual(automation.reads.count, 1)
    }

    func testPreferredPlayerIsPolledEveryThreeSecondsWithThePanelClosed() {
        coordinator.startMonitoring()
        coordinator.follow(ScriptablePlayer.music.rawValue)
        XCTAssertEqual(automation.reads.count, 1)

        scheduler.advance(by: 2.9)
        XCTAssertEqual(automation.reads.count, 1)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(automation.reads.count, 2)
    }

    func testAnExitedHelperIsRestartedWithABackoff() {
        coordinator.startMonitoring()
        XCTAssertEqual(adapter.startCount, 1)

        adapter.fail()
        scheduler.advance(by: 4.9)
        XCTAssertEqual(adapter.startCount, 1)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(adapter.startCount, 2)

        adapter.fail()
        scheduler.advance(by: 29.9)
        XCTAssertEqual(adapter.startCount, 2)
        scheduler.advance(by: 0.1)
        XCTAssertEqual(adapter.startCount, 3)

        adapter.fail()
        scheduler.advance(by: 300)
        XCTAssertEqual(adapter.startCount, 4)
        adapter.fail()
        scheduler.advance(by: 300)
        XCTAssertEqual(adapter.startCount, 5)
    }

    func testASuccessfulUpdateResetsTheBackoff() {
        coordinator.startMonitoring()
        adapter.fail()
        scheduler.advance(by: 5)
        adapter.emit(track(.music))
        adapter.fail()
        scheduler.advance(by: 5)
        XCTAssertEqual(adapter.startCount, 3)
    }

    func testNoRestartAfterMonitoringStops() {
        coordinator.startMonitoring()
        adapter.fail()
        coordinator.stopMonitoring()
        scheduler.advance(by: 600)
        XCTAssertEqual(adapter.startCount, 1)
    }

    func testPlayerIsNotPolledUntilItRuns() {
        discovery.running = []
        coordinator.startMonitoring()
        coordinator.follow(ScriptablePlayer.spotify.rawValue)

        XCTAssertTrue(automation.reads.isEmpty)
        XCTAssertEqual(coordinator.current, nil)
    }

    func testPollingStopsWithMonitoring() {
        coordinator.startMonitoring()
        coordinator.follow(ScriptablePlayer.music.rawValue)
        XCTAssertEqual(automation.reads.count, 1)

        coordinator.stopMonitoring()
        scheduler.advance(by: 5)

        XCTAssertEqual(automation.reads.count, 1)
        XCTAssertEqual(adapter.stopCount, 1)
    }

    func testCommandsRouteToThePreferredPlayer() {
        coordinator.startMonitoring()
        automation.snapshots[.music] = track(.music)
        coordinator.follow(ScriptablePlayer.music.rawValue)

        coordinator.send(.next)
        coordinator.seek(to: 30)

        XCTAssertEqual(automation.commands.count, 1)
        XCTAssertEqual(automation.commands.first?.command, .next)
        XCTAssertEqual(automation.commands.first?.player, .music)
        XCTAssertEqual(automation.seeks.first?.position, 30)
        XCTAssertTrue(adapter.commands.isEmpty)
    }

    func testCommandsUseTheAdapterInAutomaticMode() {
        coordinator.startMonitoring()
        coordinator.follow(nil)
        adapter.emit(track(.spotify))

        coordinator.send(.togglePlayPause)
        coordinator.seek(to: 12)

        XCTAssertEqual(adapter.commands, [.togglePlayPause])
        XCTAssertEqual(adapter.seeks, [12])
        XCTAssertTrue(automation.commands.isEmpty)
    }

    func testStopClearsTheCurrentTrack() {
        coordinator.startMonitoring()
        adapter.emit(track(.safari))
        XCTAssertNotNil(coordinator.current)

        coordinator.stopMonitoring()

        XCTAssertNil(coordinator.current)
        XCTAssertEqual(adapter.stopCount, 1)
    }

    func testStartingTwiceOnlyStartsTheAdapterOnce() {
        coordinator.startMonitoring()
        coordinator.startMonitoring()
        XCTAssertEqual(adapter.startCount, 1)
    }

    func testSourcesAreTheInstalledPlayers() {
        XCTAssertEqual(coordinator.sources.map(\.id), [ScriptablePlayer.spotify.rawValue,
                                                       ScriptablePlayer.music.rawValue])
    }

    func testAdapterFailureReportsUnavailable() {
        coordinator.startMonitoring()
        adapter.fail()

        XCTAssertFalse(coordinator.isAvailable)
        XCTAssertNil(coordinator.current)
    }

    func testUpdatesArePublishedOnlyWhenTheTrackChanges() {
        var updates = 0
        coordinator.onUpdate = { _ in updates += 1 }

        coordinator.startMonitoring()
        let emitted = track(.spotify)
        adapter.emit(emitted)
        adapter.emit(emitted)

        XCTAssertEqual(updates, 1)
    }
}
