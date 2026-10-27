import XCTest
@testable import AvatarCore

final class ActTests: XCTestCase {
    func decode(_ s: String) throws -> Request {
        try JSONDecoder().decode(Request.self, from: s.data(using: .utf8)!)
    }

    func testDecodesAct() throws {
        XCTAssertEqual(try decode(#"{"type":"act","action":"scroll","x":5,"y":6,"dir":"down","source":"input"}"#),
                       .act(ActRequest(action: .scroll, x: 5, y: 6, dir: .down, source: "input")))
        XCTAssertEqual(try decode(#"{"type":"act","action":"type"}"#), .act(ActRequest(action: .type)))
        XCTAssertThrowsError(try decode(#"{"type":"act","action":"wiggle"}"#))
    }

    func testClickShowsTapAtPointThenBusyPoseReturnsAtOnce() {
        let d = Director(now: 0)
        d.handle(.state(.working, note: nil, activity: "browsing"), at: 0)
        d.handle(.act(ActRequest(action: .click, x: 100, y: 200)), at: 10)
        XCTAssertEqual(d.directive(at: 10.1), Directive(pose: "tap", target: .rect(Rect(x: 100, y: 200, w: 1, h: 1))))
        // hold is 0.8 s; no minDwell after an act
        XCTAssertEqual(d.directive(at: 10.9).pose, "search")
    }

    func testScrollAndTypeMapping() {
        XCTAssertEqual(Director.showRequest(for: ActRequest(action: .scroll, x: 1, y: 2, dir: .up)),
                       ShowRequest(pose: "scroll", at: .rect(Rect(x: 1, y: 2, w: 1, h: 1)), fx: "scroll_up"))
        XCTAssertEqual(Director.showRequest(for: ActRequest(action: .scroll, x: 1, y: 2)).fx, "scroll_down")
        XCTAssertEqual(Director.showRequest(for: ActRequest(action: .type)), ShowRequest(pose: "type"))
        XCTAssertEqual(Director.showRequest(for: ActRequest(action: .drag, x: 3, y: 4)).pose, "tap")
    }

    func testIsBusy() {
        let d = Director(now: 0)
        XCTAssertFalse(d.isBusy(at: 0))
        d.handle(.state(.working, note: nil), at: 1)
        XCTAssertTrue(d.isBusy(at: 2))
        XCTAssertFalse(d.isBusy(at: 1 + DirectorConfig().staleBusy))
        d.handle(.state(.done, note: nil), at: 3)
        XCTAssertFalse(d.isBusy(at: 3))
    }

    func testIsActingOnlyDuringAct() {
        let d = Director(now: 0)
        XCTAssertFalse(d.isActing(at: 0))
        d.handle(.show(ShowRequest(pose: "wave")), at: 0)
        XCTAssertFalse(d.isActing(at: 0.5))
        d.handle(.act(ActRequest(action: .click, x: 1, y: 2)), at: 1)
        XCTAssertTrue(d.isActing(at: 1.5))
        XCTAssertFalse(d.isActing(at: 1.9))
    }

    func testActResumesInterruptedShow() {
        let d = Director(now: 0)
        d.handle(.show(ShowRequest(pose: "wave", say: "hi", holdS: 4)), at: 0)
        d.handle(.act(ActRequest(action: .click, x: 1, y: 2)), at: 1)
        XCTAssertEqual(d.directive(at: 1.1).pose, "tap")
        let back = d.directive(at: 2.0)
        XCTAssertEqual(back.pose, "wave")
        XCTAssertEqual(back.say, "hi")
        XCTAssertNil(d.directive(at: 5).say)
    }

    func testPoselessShowAfterActKeepsRestingPose() {
        let d = Director(now: 0)
        d.handle(.state(.working, note: nil), at: 0)
        XCTAssertEqual(d.directive(at: 0).pose, "work")
        d.handle(.act(ActRequest(action: .click, x: 1, y: 2)), at: 1)
        XCTAssertEqual(d.directive(at: 1.1).pose, "tap")
        d.handle(.show(ShowRequest(say: "done")), at: 1.2)
        let out = d.directive(at: 1.3)
        XCTAssertEqual(out.pose, "work")
        XCTAssertEqual(out.say, "done")
    }

    func testActKeepsBusyAlive() {
        let d = Director(now: 0)
        d.handle(.state(.working, note: nil), at: 0)
        d.handle(.act(ActRequest(action: .click, x: 1, y: 2)), at: 100)
        XCTAssertTrue(d.isBusy(at: 150))
    }
}
