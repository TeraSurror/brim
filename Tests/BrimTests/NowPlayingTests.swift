import XCTest
@testable import BrimKit

final class NowPlayingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func track(
        duration: TimeInterval = 200,
        elapsed: TimeInterval = 10,
        playing: Bool = true
    ) -> NowPlaying {
        NowPlaying(
            title: "Track",
            duration: duration,
            elapsed: elapsed,
            capturedAt: start,
            isPlaying: playing,
            source: .spotify
        )
    }

    func testPlayingPositionAdvancesWithTime() {
        let track = track()
        XCTAssertEqual(track.position(at: start), 10, accuracy: 0.001)
        XCTAssertEqual(track.position(at: start.addingTimeInterval(30)), 40, accuracy: 0.001)
    }

    func testPausedPositionDoesNotAdvance() {
        let track = track(playing: false)
        XCTAssertEqual(track.position(at: start.addingTimeInterval(30)), 10, accuracy: 0.001)
    }

    func testPositionIsClampedToTheTrack() {
        let track = track(duration: 20, elapsed: 18)
        XCTAssertEqual(track.position(at: start.addingTimeInterval(60)), 20, accuracy: 0.001)
    }

    func testPositionNeverGoesBelowZero() {
        let track = track(elapsed: 0)
        XCTAssertEqual(track.position(at: start.addingTimeInterval(-30)), 0, accuracy: 0.001)
    }

    func testUnknownDurationReportsRawPosition() {
        let track = track(duration: 0, elapsed: 5)
        XCTAssertEqual(track.position(at: start.addingTimeInterval(5)), 10, accuracy: 0.001)
    }

    func testRemainingNeverGoesBelowZero() {
        let track = track(duration: 20, elapsed: 18)
        XCTAssertEqual(track.remaining(at: start), 2, accuracy: 0.001)
        XCTAssertEqual(track.remaining(at: start.addingTimeInterval(60)), 0, accuracy: 0.001)
    }

    func testSourceFallsBackToBundleIdentifier() {
        let source = NowPlayingSource(bundleIdentifier: "com.example.awesome-player")
        XCTAssertEqual(source.id, "com.example.awesome-player")
        XCTAssertEqual(source.name, "awesome player")
    }

    func testArtworkEqualityUsesTheContentHash() {
        let first = NowPlayingArtwork(data: Data("image".utf8))
        let second = NowPlayingArtwork(data: Data("image".utf8))
        let other = NowPlayingArtwork(data: Data("other".utf8))

        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, other)
        XCTAssertEqual(first.id.count, 64)
    }
}
