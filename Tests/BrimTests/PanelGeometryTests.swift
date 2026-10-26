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

    func testExpandedIsCenteredAndTopAnchored() {
        let metrics = PanelMetrics()
        let geometry = PanelGeometry(screen: notched, metrics: metrics)
        let expanded = geometry.frame(for: .expanded)

        XCTAssertEqual(expanded.minY, 0)
        XCTAssertEqual(expanded.midX, notched.frame.midX)
        XCTAssertEqual(expanded.height, metrics.expandedHeight)
        XCTAssertEqual(expanded.width, metrics.expandedWidth)
    }

    func testLiveNotchAddsAnEarOnEachSideAtNotchHeight() {
        let metrics = PanelMetrics()
        let geometry = PanelGeometry(screen: notched, metrics: metrics)
        let notch = notched.notchRect!
        let live = geometry.frame(for: .collapsed, live: true)

        XCTAssertEqual(live, geometry.liveFrame)
        XCTAssertEqual(live.width, notch.width + metrics.liveEarWidth * 2)
        XCTAssertEqual(live.height, notch.height)
        XCTAssertEqual(live.midX, notch.midX)
        XCTAssertEqual(live.minY, notch.minY)
    }

    func testLiveNotchOnAPlainScreenIsATopCenteredPill() {
        let metrics = PanelMetrics()
        let geometry = PanelGeometry(screen: plain, metrics: metrics)
        let live = geometry.liveFrame

        XCTAssertEqual(live.size, metrics.livePillSize)
        XCTAssertEqual(live.midX, plain.frame.midX)
        XCTAssertEqual(live.minY, plain.frame.minY)
    }

    func testLivePillMatchesTheMenuBarHeight() {
        var screen = plain
        screen.menuBarHeight = 30
        let live = PanelGeometry(screen: screen).liveFrame

        XCTAssertEqual(live.height, 30)
        XCTAssertEqual(live.width, PanelMetrics().livePillSize.width)
        XCTAssertEqual(live.minY, plain.frame.minY)
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

        XCTAssertEqual(geometry.frame(for: .expanded).width, 300 - metrics.screenMargin * 2)
        XCTAssertEqual(geometry.liveFrame.width, min(metrics.livePillSize.width, 300 - metrics.screenMargin * 2))
    }

    func testExpandedWidthGrowsWithTheModuleCount() {
        XCTAssertEqual(PanelMetrics.expandedWidth(forModuleCount: 0), PanelMetrics.minimumExpandedWidth)
        XCTAssertEqual(PanelMetrics.expandedWidth(forModuleCount: 1), PanelMetrics.minimumExpandedWidth)
        // Two cards of 290 + 14 spacing + 18 padding each side.
        XCTAssertEqual(PanelMetrics.expandedWidth(forModuleCount: 2), 630)
        XCTAssertEqual(PanelMetrics.expandedWidth(forModuleCount: 3), 934)

        let geometry = PanelGeometry(screen: notched, metrics: PanelMetrics(moduleCount: 3))
        XCTAssertEqual(geometry.frame(for: .expanded).width, 934)
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
        XCTAssertFalse(geometry.contains(CGPoint(x: 630, y: 16), in: .collapsed))
        XCTAssertTrue(geometry.contains(CGPoint(x: 630, y: 16), in: .collapsed, live: true))
    }
}
