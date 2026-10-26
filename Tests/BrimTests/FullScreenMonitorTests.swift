import XCTest
@testable import BrimKit

/// Window lists recorded on the development machine: a notched built-in display to the right of a 1080p
/// external, before and while a window was full screen on each.
@MainActor
final class FullScreenMonitorTests: XCTestCase {
    private let ownPID: pid_t = 100
    private let appPID: pid_t = 200
    private let otherPID: pid_t = 300
    private let finderPID: pid_t = 400
    private let desktopLayer = Int(CGWindowLevelForKey(.desktopIconWindow))

    private var external: ScreenInfo!
    private var builtIn: ScreenInfo!

    override func setUp() {
        super.setUp()
        external = ScreenInfo(
            id: "external",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            menuBarHeight: 30
        )
        builtIn = ScreenInfo(
            id: "built-in",
            frame: CGRect(x: 1920, y: 0, width: 1470, height: 956),
            auxiliaryLeftWidth: 646,
            auxiliaryRightWidth: 645,
            topInset: 32,
            menuBarHeight: 33
        )
    }

    private func desktop(on screen: ScreenInfo) -> WindowSnapshot {
        WindowSnapshot(ownerPID: finderPID, layer: desktopLayer, bounds: screen.frame)
    }

    private func covered(_ windows: [WindowSnapshot]) -> Set<String> {
        WorkspaceFullScreenMonitor.coveredScreenIDs(
            windows: windows,
            screens: [external, builtIn],
            excludingPID: ownPID
        )
    }

    func testZoomedWindowsOnADesktopAreNotFullScreen() {
        let windows = [
            WindowSnapshot(ownerPID: appPID, layer: 0, bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)),
            WindowSnapshot(ownerPID: otherPID, layer: 0, bounds: CGRect(x: 1920, y: 33, width: 1470, height: 923)),
            desktop(on: external),
            desktop(on: builtIn),
        ]
        XCTAssertEqual(covered(windows), [])
    }

    func testFullScreenBelowTheNotchCoversTheBuiltInDisplayOnly() {
        // On a notched display a full-screen window stops below the menu bar strip, like a zoomed one.
        let windows = [
            WindowSnapshot(ownerPID: appPID, layer: 26, bounds: CGRect(x: 1920, y: 0, width: 1470, height: 33), alpha: 0),
            WindowSnapshot(ownerPID: appPID, layer: 0, bounds: CGRect(x: 1920, y: 33, width: 1470, height: 923)),
            WindowSnapshot(ownerPID: otherPID, layer: 0, bounds: CGRect(x: 0, y: 30, width: 1920, height: 1050)),
            desktop(on: external),
        ]
        XCTAssertEqual(covered(windows), ["built-in"])
    }

    func testFullScreenOnTheExternalDisplayCoversTheWholeFrame() {
        let windows = [
            WindowSnapshot(ownerPID: appPID, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            WindowSnapshot(ownerPID: otherPID, layer: 0, bounds: CGRect(x: 1920, y: 33, width: 1470, height: 923)),
            desktop(on: builtIn),
        ]
        XCTAssertEqual(covered(windows), ["external"])
    }

    func testASpaceWithoutAFillingWindowIsNotFullScreen() {
        let windows = [
            WindowSnapshot(ownerPID: appPID, layer: 0, bounds: CGRect(x: 2100, y: 200, width: 800, height: 500)),
            desktop(on: external),
        ]
        XCTAssertEqual(covered(windows), [])
    }

    func testBrimsOwnTransparentAndOverlayWindowsAreIgnored() {
        let frame = CGRect(x: 1920, y: 0, width: 1470, height: 956)
        let windows = [
            WindowSnapshot(ownerPID: ownPID, layer: 0, bounds: frame),
            WindowSnapshot(ownerPID: appPID, layer: 0, bounds: frame, alpha: 0),
            WindowSnapshot(ownerPID: appPID, layer: 25, bounds: frame),
            desktop(on: external),
        ]
        XCTAssertEqual(covered(windows), [])
    }
}
