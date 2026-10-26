import XCTest
@testable import BrimKit

@MainActor
final class PanelStateMachineTests: XCTestCase {
    private var scheduler: FakeScheduler!
    private var machine: PanelStateMachine!
    private let notched = ScreenInfo(
        id: "built-in",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        auxiliaryLeftWidth: 650,
        auxiliaryRightWidth: 650,
        topInset: 32
    )

    override func setUp() async throws {
        scheduler = FakeScheduler()
        machine = PanelStateMachine(
            screen: notched,
            timings: PanelTimings(hoverDelay: 0.15, collapseDelay: 0.4),
            scheduler: scheduler
        )
    }

    private let notchPoint = CGPoint(x: 756, y: 16)
    /// Inside the left ear of the live notch (notch is x 650…862, ears add 40 pt per side), outside the notch.
    private let earPoint = CGPoint(x: 630, y: 16)
    private let away = CGPoint(x: 756, y: 500)

    func testHoverOpensTheFullPanelAfterTheHoverDelay() {
        machine.pointerMoved(to: notchPoint)
        scheduler.advance(by: 0.14)
        XCTAssertEqual(machine.state, .collapsed)
        scheduler.advance(by: 0.02)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testClickOpensTheFullPanelImmediately() {
        machine.clicked(at: notchPoint)
        XCTAssertEqual(machine.state, .expanded)
        scheduler.advance(by: 10)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testClickModeIgnoresHoverButOpensOnClick() {
        machine.update(timings: PanelTimings(hoverDelay: 0.15, collapseDelay: 0.4, opensOnHover: false))
        machine.pointerMoved(to: notchPoint)
        scheduler.advance(by: 2)
        XCTAssertEqual(machine.state, .collapsed)

        machine.clicked(at: notchPoint)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testSwitchingToClickModeCancelsAPendingHover() {
        machine.pointerMoved(to: notchPoint)
        scheduler.advance(by: 0.1)
        machine.update(timings: PanelTimings(hoverDelay: 0.15, collapseDelay: 0.4, opensOnHover: false))
        scheduler.advance(by: 1)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testLeavingExpandedCollapsesAfterTheDelay() {
        machine.clicked(at: notchPoint)
        machine.pointerMoved(to: away)
        scheduler.advance(by: 0.39)
        XCTAssertEqual(machine.state, .expanded)
        scheduler.advance(by: 0.02)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testComingBackCancelsTheCollapse() {
        machine.clicked(at: notchPoint)
        machine.pointerMoved(to: away)
        scheduler.advance(by: 0.2)
        machine.pointerMoved(to: notchPoint)
        scheduler.advance(by: 5)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testTheExitAreaIsLargerThanThePanel() {
        machine.clicked(at: notchPoint)
        // Expanded panel is 320 tall; 8 pt below still counts, 40 pt below does not.
        machine.pointerMoved(to: CGPoint(x: 756, y: 328))
        scheduler.advance(by: 1)
        XCTAssertEqual(machine.state, .expanded)

        machine.pointerMoved(to: CGPoint(x: 756, y: 360))
        scheduler.advance(by: 0.41)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testLeavingBeforeTheDelayCancelsTheOpen() {
        machine.pointerMoved(to: notchPoint)
        scheduler.advance(by: 0.1)
        machine.pointerMoved(to: away)
        scheduler.advance(by: 2)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testClickingAwayDoesNothing() {
        machine.clicked(at: CGPoint(x: 100, y: 500))
        scheduler.advance(by: 2)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testDisablingCollapsesImmediately() {
        machine.clicked(at: notchPoint)
        machine.isEnabled = false
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testStateChangeCallbackReportsEveryTransition() {
        var states: [PanelState] = []
        machine.onStateChange = { states.append($0) }

        machine.pointerMoved(to: notchPoint)
        scheduler.advance(by: 0.15)
        machine.pointerMoved(to: away)
        scheduler.advance(by: 0.4)

        XCTAssertEqual(states, [.expanded, .collapsed])
    }

    func testTheEarsAreAHoverTargetOnlyWhileLive() {
        machine.pointerMoved(to: earPoint)
        scheduler.advance(by: 1)
        XCTAssertEqual(machine.state, .collapsed)

        machine.isLive = true
        machine.pointerMoved(to: earPoint)
        scheduler.advance(by: 0.15)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testClickingAnEarOpensThePanel() {
        machine.isLive = true
        machine.clicked(at: earPoint)
        XCTAssertEqual(machine.state, .expanded)
    }

    func testEarsAppearingUnderARestingPointerDoNotOpenThePanel() {
        machine.pointerMoved(to: earPoint)
        machine.isLive = true
        scheduler.advance(by: 1)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testEarsDisappearingCancelsAPendingOpen() {
        machine.isLive = true
        machine.pointerMoved(to: earPoint)
        scheduler.advance(by: 0.1)
        machine.isLive = false
        scheduler.advance(by: 1)
        XCTAssertEqual(machine.state, .collapsed)
    }

    func testPlainScreenHandleWorksTheSameWay() {
        let plain = ScreenInfo(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let handleMachine = PanelStateMachine(
            screen: plain,
            timings: PanelTimings(hoverDelay: 0.15, collapseDelay: 0.4),
            scheduler: scheduler
        )

        handleMachine.pointerMoved(to: CGPoint(x: 960, y: 5))
        scheduler.advance(by: 0.15)
        XCTAssertEqual(handleMachine.state, .expanded)
    }
}
