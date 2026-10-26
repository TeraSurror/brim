import XCTest
@testable import BrimKit

final class AgentAlertGeometryTests: XCTestCase {
    private func screen(
        width: CGFloat = 1920,
        topInset: CGFloat = 0,
        auxiliaryLeft: CGFloat? = nil,
        auxiliaryRight: CGFloat? = nil
    ) -> ScreenInfo {
        ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: width, height: 1080),
            auxiliaryLeftWidth: auxiliaryLeft,
            auxiliaryRightWidth: auxiliaryRight,
            topInset: topInset
        )
    }

    func testSitsUnderTheNotch() {
        let notchScreen = screen(topInset: 32, auxiliaryLeft: 700, auxiliaryRight: 1041)
        let frame = AgentAlertGeometry.frame(for: notchScreen)

        XCTAssertEqual(frame.midX, notchScreen.notchRect?.midX)
        XCTAssertEqual(frame.minY, 40)
        XCTAssertEqual(frame.width, AgentAlertGeometry.size.width)
        XCTAssertEqual(frame.height, AgentAlertGeometry.size.height)
    }

    func testCentersOnAPlainScreen() {
        let frame = AgentAlertGeometry.frame(for: screen())

        XCTAssertEqual(frame.midX, 960)
        XCTAssertEqual(frame.minY, 8)
    }

    func testClampsTheWidthToANarrowScreen() {
        let frame = AgentAlertGeometry.frame(for: screen(width: 320))

        XCTAssertEqual(frame.width, 296)
        XCTAssertGreaterThanOrEqual(frame.minX, 8)
    }

    func testUsesTheNotchCenterEvenWhenTheScreenIsWide() {
        let notchScreen = screen(topInset: 32, auxiliaryLeft: 870.5, auxiliaryRight: 870.5)
        let frame = AgentAlertGeometry.frame(for: notchScreen)

        XCTAssertEqual(frame.midX, 960)
    }
}
