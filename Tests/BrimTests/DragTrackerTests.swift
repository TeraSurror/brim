import XCTest
@testable import BrimKit

@MainActor
final class DragTrackerTests: XCTestCase {
    private var tracker: DragTracker!
    private var typeReads = 0

    override func setUp() {
        super.setUp()
        tracker = DragTracker()
        typeReads = 0
    }

    private func drag(_ changeCount: Int, types: Set<DropKind> = [.files]) -> Set<DropKind>? {
        tracker.dragged(changeCount: changeCount) {
            typeReads += 1
            return types
        }
    }

    func testAPlainDragIsNotAContentDrag() {
        tracker.mouseDown(changeCount: 4)
        XCTAssertNil(drag(4))
        XCTAssertNil(drag(4))
        XCTAssertEqual(typeReads, 0)
    }

    func testAContentDragReportsItsKindsAndReadsTypesOnce() {
        tracker.mouseDown(changeCount: 4)
        XCTAssertEqual(drag(5, types: [.files, .text]), [.files, .text])
        XCTAssertEqual(drag(5), [.files, .text])
        XCTAssertEqual(typeReads, 1)
    }

    func testMouseUpEndsTheDrag() {
        tracker.mouseDown(changeCount: 4)
        _ = drag(5)
        tracker.mouseUp()
        XCTAssertNil(tracker.kinds)
        XCTAssertNil(drag(6))
    }

    func testADragWithoutAMouseDownIsIgnored() {
        XCTAssertNil(drag(9))
    }

    func testUnknownContentIsIgnoredForTheRestOfTheDrag() {
        tracker.mouseDown(changeCount: 4)
        XCTAssertNil(drag(5, types: []))
        XCTAssertNil(drag(6, types: [.files]))
        XCTAssertEqual(typeReads, 1)
    }
}
