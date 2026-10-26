import XCTest
@testable import AvatarCore

final class GeometryTests: XCTestCase {
    func testContainsAndEdges() {
        let outer = Rect(x: 0, y: 25, w: 1440, h: 800)
        XCTAssertEqual(outer.maxX, 1440)
        XCTAssertEqual(outer.maxY, 825)
        XCTAssertTrue(outer.contains(Rect(x: 10, y: 30, w: 100, h: 100)))
        XCTAssertFalse(outer.contains(Rect(x: 10, y: 0, w: 100, h: 100)))   // pokes above (into menu bar)
        XCTAssertFalse(outer.contains(Rect(x: 1400, y: 30, w: 100, h: 100))) // pokes off the right
    }

    func testIntersectionArea() {
        let a = Rect(x: 0, y: 0, w: 100, h: 100)
        XCTAssertEqual(a.intersectionArea(Rect(x: 50, y: 50, w: 100, h: 100)), 2500)
        XCTAssertEqual(a.intersectionArea(Rect(x: 200, y: 0, w: 10, h: 10)), 0)
    }

    func testVisionRectToScreen() {
        // Vision boxes are normalized, origin bottom-left.
        let r = visionRectToScreen(0.5, 0.0, 0.25, 0.1, in: Rect(x: 100, y: 200, w: 400, h: 300))
        XCTAssertEqual(r, Rect(x: 300, y: 470, w: 100, h: 30))
    }
}
