import XCTest
@testable import BrimKit

@MainActor
final class GestureInterpreterTests: XCTestCase {
    private var interpreter: GestureInterpreter!
    private let notch = CGPoint(x: 756, y: 16)

    override func setUp() {
        super.setUp()
        interpreter = GestureInterpreter()
    }

    private func feed(
        _ phase: ScrollSample.Phase,
        dx: CGFloat = 0,
        dy: CGFloat = 0,
        momentum: Bool = false,
        at time: TimeInterval = 0,
        location: CGPoint? = nil
    ) -> ScrollGesture? {
        interpreter.feed(ScrollSample(
            location: location ?? notch,
            deltaX: dx,
            deltaY: dy,
            phase: phase,
            isMomentum: momentum,
            timestamp: time
        ))?.gesture
    }

    func testATrackpadSwipeDownFiresOnceWhenItPassesTheThreshold() {
        XCTAssertNil(feed(.began, dy: 3))
        XCTAssertNil(feed(.changed, dy: 4))
        XCTAssertEqual(feed(.changed, dy: 4), .down)
        XCTAssertNil(feed(.changed, dy: 40))
        XCTAssertNil(feed(.ended))
    }

    func testTheGestureReportsWhereItStarted() {
        _ = feed(.began, dy: 2, location: notch)
        let result = interpreter.feed(ScrollSample(
            location: CGPoint(x: 900, y: 200), deltaY: 20, phase: .changed, timestamp: 0))
        XCTAssertEqual(result?.location, notch)
    }

    func testMomentumNeverFires() {
        XCTAssertNil(feed(.none, dx: -80, momentum: true))
        XCTAssertNil(feed(.none, dy: 80, momentum: true))
    }

    func testHorizontalSwipesNeedMoreTravelThanVerticalOnes() {
        XCTAssertNil(feed(.began, dx: -10))
        XCTAssertNil(feed(.changed, dx: -10))
        XCTAssertEqual(feed(.changed, dx: -10), .left)
        _ = feed(.ended)

        XCTAssertNil(feed(.began, dx: 12))
        XCTAssertEqual(feed(.changed, dx: 14), .right)
    }

    func testADiagonalDriftDoesNothing() {
        XCTAssertNil(feed(.began, dx: 20, dy: 18))
        XCTAssertNil(feed(.changed, dx: 20, dy: 18))
    }

    func testEachSwipeIsOneAction() {
        _ = feed(.began, dx: -30)
        _ = feed(.ended)
        XCTAssertNil(feed(.none, dx: -60, momentum: true))
        XCTAssertEqual(feed(.began, dx: -30), .left)
    }

    func testUpIsTheOppositeOfDown() {
        XCTAssertEqual(feed(.began, dy: -12), .up)
    }

    func testMouseWheelStepsFireWithACooldown() {
        XCTAssertEqual(feed(.none, dy: 1, at: 10), .down)
        XCTAssertNil(feed(.none, dy: 1, at: 10.1))
        XCTAssertNil(feed(.none, dy: 1, at: 10.3))
        XCTAssertEqual(feed(.none, dy: -1, at: 10.5), .up)
    }
}
