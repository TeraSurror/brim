import XCTest
@testable import BrimKit

@MainActor
final class DisplayModeTests: XCTestCase {
    private var main: ScreenInfo!
    private var builtIn: ScreenInfo!
    private var side: ScreenInfo!

    override func setUp() {
        super.setUp()
        main = ScreenInfo(id: "main", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), menuBarHeight: 30)
        builtIn = ScreenInfo(
            id: "built-in",
            frame: CGRect(x: 1920, y: 0, width: 1470, height: 956),
            auxiliaryLeftWidth: 646,
            auxiliaryRightWidth: 645,
            topInset: 32
        )
        side = ScreenInfo(id: "side", frame: CGRect(x: -1440, y: 0, width: 1440, height: 900))
    }

    func testAllDisplaysKeepsEveryScreenInOrder() {
        XCTAssertEqual(DisplayMode.all.screens(in: [main, builtIn, side]).map(\.id), ["main", "built-in", "side"])
    }

    func testNotchedOnlyKeepsTheNotchedScreen() {
        XCTAssertEqual(DisplayMode.notchedOnly.screens(in: [main, builtIn, side]).map(\.id), ["built-in"])
    }

    func testNotchedOnlyFallsBackToTheMainDisplayWithTheLidClosed() {
        XCTAssertEqual(DisplayMode.notchedOnly.screens(in: [main, side]).map(\.id), ["main"])
    }

    func testMainOnlyKeepsTheFirstScreenEvenWhenAnotherHasTheNotch() {
        XCTAssertEqual(DisplayMode.mainOnly.screens(in: [main, builtIn]).map(\.id), ["main"])
        XCTAssertEqual(DisplayMode.mainOnly.screens(in: [builtIn, main]).map(\.id), ["built-in"])
    }

    func testNoScreensGivesNoPanels() {
        for mode in DisplayMode.allCases {
            XCTAssertTrue(mode.screens(in: []).isEmpty)
        }
    }

    func testTheAlertUsesAShownDisplayWhenThePointerIsElsewhere() {
        let shown = DisplayMode.notchedOnly.screens(in: [main, builtIn])
        let onMain = CGPoint(x: 500, y: 500)
        XCTAssertEqual(AgentAlertGeometry.screen(for: onMain, in: shown)?.id, "built-in")
    }
}
