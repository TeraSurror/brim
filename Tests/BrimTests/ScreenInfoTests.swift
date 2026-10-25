import XCTest
@testable import BrimKit

final class ScreenInfoTests: XCTestCase {
    func testNotchRectFromRecordedMacBookPro() {
        // 14-inch MacBook Pro, menu bar areas on either side of a 212 pt notch.
        let screen = ScreenInfo(
            id: "built-in",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            auxiliaryLeftWidth: 650,
            auxiliaryRightWidth: 650,
            topInset: 32
        )

        XCTAssertEqual(
            screen.notchRect,
            CGRect(x: 650, y: 0, width: 212, height: 32)
        )
        XCTAssertEqual(screen.notchRect?.midX, screen.frame.midX)
    }

    func testExternalDisplayHasNoNotch() {
        let screen = ScreenInfo(
            id: "external",
            frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
            topInset: 0
        )
        XCTAssertNil(screen.notchRect)
        XCTAssertFalse(screen.hasNotch)
    }

    func testNotchNeedsBothAuxiliaryAreas() {
        let missingRight = ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            auxiliaryLeftWidth: 650,
            topInset: 32
        )
        let missingLeft = ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            auxiliaryRightWidth: 650,
            topInset: 32
        )
        XCTAssertNil(missingRight.notchRect)
        XCTAssertNil(missingLeft.notchRect)
    }

    func testInvalidAuxiliaryWidthsAreNotANotch() {
        let tooWide = ScreenInfo(
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            auxiliaryLeftWidth: 900,
            auxiliaryRightWidth: 900,
            topInset: 32
        )
        XCTAssertNil(tooWide.notchRect)
    }

    func testNotchFollowsScreenOriginOnTheRight() {
        let screen = ScreenInfo(
            frame: CGRect(x: 1512, y: 0, width: 1512, height: 982),
            auxiliaryLeftWidth: 650,
            auxiliaryRightWidth: 650,
            topInset: 32
        )
        XCTAssertEqual(screen.notchRect?.minX, 2162)
        XCTAssertEqual(screen.notchRect?.midX, 2268)
    }
}
