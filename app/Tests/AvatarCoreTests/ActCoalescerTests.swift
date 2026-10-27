import XCTest
@testable import AvatarCore

final class ActCoalescerTests: XCTestCase {
    func testEveryClickIsAnAct() {
        let c = ActCoalescer()
        XCTAssertEqual(c.feed(.click(x: 1, y: 2), at: 0), ActRequest(action: .click, x: 1, y: 2, source: "input"))
        XCTAssertEqual(c.feed(.click(x: 3, y: 4), at: 0.05)?.x, 3)
    }

    func testScrollBurstEmitsOnceUntilPauseOrFlip() {
        let c = ActCoalescer()
        XCTAssertEqual(c.feed(.scroll(x: 5, y: 6, dy: -3), at: 0), ActRequest(action: .scroll, x: 5, y: 6, dir: .down, source: "input"))
        XCTAssertNil(c.feed(.scroll(x: 5, y: 6, dy: -2), at: 0.1))
        XCTAssertNil(c.feed(.scroll(x: 5, y: 6, dy: -2), at: 0.35))   // still inside the burst (gap 0.25)
        XCTAssertEqual(c.feed(.scroll(x: 5, y: 6, dy: 4), at: 0.4)?.dir, .up)  // flip
        XCTAssertEqual(c.feed(.scroll(x: 5, y: 6, dy: 1), at: 1.0)?.dir, .up)  // pause
        XCTAssertNil(c.feed(.scroll(x: 5, y: 6, dy: 0), at: 2.0))
    }

    func testTypingBurstIsPlacedAtRecentClick() {
        let c = ActCoalescer()
        XCTAssertEqual(c.feed(.key, at: 0), ActRequest(action: .type, source: "input"))
        _ = c.feed(.click(x: 10, y: 20), at: 5)
        XCTAssertEqual(c.feed(.key, at: 6), ActRequest(action: .type, x: 10, y: 20, source: "input"))
        XCTAssertNil(c.feed(.key, at: 6.5))
        XCTAssertEqual(c.feed(.key, at: 12)?.x, nil)  // burst over and the click is stale
    }
}
