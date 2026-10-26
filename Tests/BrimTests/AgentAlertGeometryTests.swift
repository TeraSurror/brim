import XCTest
@testable import BrimKit

final class AgentAlertGeometryTests: XCTestCase {
    private func screen(
        x: CGFloat = 0,
        width: CGFloat = 1920,
        topInset: CGFloat = 0,
        auxiliaryLeft: CGFloat? = nil,
        auxiliaryRight: CGFloat? = nil
    ) -> ScreenInfo {
        ScreenInfo(
            id: "screen-\(Int(x))",
            frame: CGRect(x: x, y: 0, width: width, height: 1080),
            auxiliaryLeftWidth: auxiliaryLeft,
            auxiliaryRightWidth: auxiliaryRight,
            topInset: topInset
        )
    }

    func testHangsFromTheTopAndClearsTheNotch() {
        let notchScreen = screen(topInset: 32, auxiliaryLeft: 700, auxiliaryRight: 1041)
        let frame = AgentAlertGeometry.frame(for: notchScreen)

        XCTAssertEqual(frame.midX, notchScreen.notchRect?.midX)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.width, AgentAlertGeometry.width)
        XCTAssertEqual(frame.height, 32 + AgentAlertGeometry.contentHeight)
    }

    func testCentersOnAPlainScreen() {
        let frame = AgentAlertGeometry.frame(for: screen())

        XCTAssertEqual(frame.midX, 960)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.height, AgentAlertGeometry.contentHeight)
    }

    func testClampsTheWidthToANarrowScreen() {
        let frame = AgentAlertGeometry.frame(for: screen(width: 320))

        XCTAssertEqual(frame.width, 296)
        XCTAssertGreaterThanOrEqual(frame.minX, 8)
        XCTAssertLessThanOrEqual(frame.maxX, 312)
    }

    func testUsesTheNotchCenterEvenWhenTheScreenIsWide() {
        let notchScreen = screen(topInset: 32, auxiliaryLeft: 870.5, auxiliaryRight: 870.5)
        XCTAssertEqual(AgentAlertGeometry.frame(for: notchScreen).midX, 960)
    }

    func testPicksTheScreenUnderThePointer() {
        let notched = screen(width: 1512, topInset: 32, auxiliaryLeft: 650, auxiliaryRight: 650)
        let external = screen(x: 1512, width: 2560)

        XCTAssertEqual(AgentAlertGeometry.screen(for: CGPoint(x: 2000, y: 500), in: [notched, external]), external)
        XCTAssertEqual(AgentAlertGeometry.screen(for: CGPoint(x: 100, y: 500), in: [external, notched]), notched)
    }

    func testFallsBackToTheNotchedScreenThenTheFirst() {
        let notched = screen(width: 1512, topInset: 32, auxiliaryLeft: 650, auxiliaryRight: 650)
        let external = screen(x: 1512, width: 2560)

        XCTAssertEqual(AgentAlertGeometry.screen(for: nil, in: [external, notched]), notched)
        XCTAssertEqual(AgentAlertGeometry.screen(for: CGPoint(x: -500, y: 0), in: [external]), external)
        XCTAssertNil(AgentAlertGeometry.screen(for: nil, in: []))
    }
}
