import XCTest
@testable import BrimKit

@MainActor
final class LiveActivityResolverTests: XCTestCase {
    private var media: LiveActivity!
    private var attention: LiveActivity!
    private var ambient: LiveActivity!

    override func setUp() async throws {
        media = LiveActivity(priority: .media)
        attention = LiveActivity(priority: .attention)
        ambient = LiveActivity(priority: .ambient)
    }

    func testNothingLiveHasNoWinner() {
        XCTAssertNil(LiveActivityResolver.winner([]))
        XCTAssertNil(LiveActivityResolver.winner([("media", nil), ("agents", nil)]))
    }

    func testHighestPriorityWins() {
        XCTAssertEqual(LiveActivityResolver.winner([("media", media), ("agents", attention)]), "agents")
        XCTAssertEqual(LiveActivityResolver.winner([("media", media), ("agents", ambient)]), "media")
    }

    func testTiesGoToTheFirstModule() {
        XCTAssertEqual(LiveActivityResolver.winner([("a", media), ("b", media)]), "a")
        XCTAssertEqual(LiveActivityResolver.winner([("b", media), ("a", media)]), "b")
    }
}
