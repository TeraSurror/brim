import XCTest
@testable import BrimKit

final class PanelGeometryTests: XCTestCase {
    private let notched = ScreenInfo(
        id: "built-in",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        auxiliaryLeftWidth: 650,
        auxiliaryRightWidth: 650,
        topInset: 32
    )
    private let plain = ScreenInfo(
        id: "external",
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    )

    func testCollapsedOnNotchedScreenIsExactlyTheNotch() {
        let geometry = PanelGeometry(screen: notched)
        XCTAssertEqual(geometry.collapsedFrame, notched.notchRect)
        XCTAssertEqual(geometry.frame(for: .collapsed), notched.notchRect)
        XCTAssertTrue(geometry.isNotched)
    }

    func testPeekAndExpandedAreCenteredAndTopAnchored() {
        let metrics = PanelMetrics()
        let geometry = PanelGeometry(screen: notched, metrics: metrics)

        let peek = geometry.frame(for: .peek)
        let expanded = geometry.frame(for: .expanded)

        XCTAssertEqual(peek.minY, 0)
        XCTAssertEqual(expanded.minY, 0)
        XCTAssertEqual(peek.midX, notched.frame.midX)
        XCTAssertEqual(expanded.midX, notched.frame.midX)
        XCTAssertEqual(peek.height, metrics.peekHeight)
        XCTAssertEqual(expanded.height, metrics.expandedHeight)
        XCTAssertGreaterThan(peek.width, notched.notchRect!.width)
        XCTAssertEqual(expanded.width, metrics.expandedWidth)
    }

    func testPlainScreenCollapsedIsASlimCenteredHandle() {
        let metrics = PanelMetrics()
        let geometry = PanelGeometry(screen: plain, metrics: metrics)
        let frame = geometry.frame(for: .collapsed)

        XCTAssertFalse(geometry.isNotched)
        XCTAssertEqual(frame.width, metrics.handleSize.width)
        XCTAssertEqual(frame.height, metrics.handleSize.height)
        XCTAssertEqual(frame.midX, plain.frame.midX)
        XCTAssertEqual(frame.minY, plain.frame.minY)
    }

    func testPanelWidthIsClampedToNarrowScreens() {
        let narrow = ScreenInfo(
            id: "narrow",
            frame: CGRect(x: 0, y: 0, width: 300, height: 700),
            topInset: 0
        )
        let metrics = PanelMetrics()
        let geometry = PanelGeometry(screen: narrow, metrics: metrics)

        XCTAssertEqual(geometry.frame(for: .peek).width, 300 - metrics.screenMargin * 2)
        XCTAssertEqual(geometry.frame(for: .expanded).width, 300 - metrics.screenMargin * 2)
    }

    func testCollapsedWindowFollowsSecondScreenOrigin() {
        let geometry = PanelGeometry(screen: plain)
        let notchLikeHandle = geometry.frame(for: .collapsed)
        XCTAssertEqual(notchLikeHandle.midX, 1512 + 1280)
        XCTAssertEqual(notchLikeHandle.minX, 1512 + 1280 - 74)
    }

    func testHitRectUsesSlopForTheExitArea() {
        let geometry = PanelGeometry(screen: notched)
        let expanded = geometry.frame(for: .expanded)
        let justBelow = CGPoint(x: expanded.midX, y: expanded.maxY + 8)
        let wellBelow = CGPoint(x: expanded.midX, y: expanded.maxY + 40)

        XCTAssertTrue(geometry.contains(justBelow, in: .expanded, slop: 12))
        XCTAssertFalse(geometry.contains(wellBelow, in: .expanded, slop: 12))
        XCTAssertTrue(geometry.contains(CGPoint(x: 756, y: 16), in: .collapsed))
        XCTAssertFalse(geometry.contains(CGPoint(x: 100, y: 16), in: .collapsed))
    }
}
