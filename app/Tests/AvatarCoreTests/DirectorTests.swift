import XCTest
@testable import AvatarCore

final class DirectorTests: XCTestCase {
    func pose(_ d: Director, _ t: Double) -> String { d.directive(at: t).pose }

    func testStartsIdleOnEdge() {
        XCTAssertEqual(Director(now: 0).directive(at: 0), Directive(pose: "lie_edge"))
    }

    func testBusyStates() {
        let d = Director(now: 0)
        d.handle(.state(.thinking, note: nil), at: 0)
        XCTAssertEqual(pose(d, 0), "think")
        d.handle(.state(.working, note: nil), at: 5)
        XCTAssertEqual(pose(d, 5), "work")
    }

    func testErrorReactsThenSettlesThenFades() {
        let d = Director(now: 0)
        d.handle(.state(.error, note: nil), at: 0)
        XCTAssertEqual(d.directive(at: 0.5), Directive(pose: "shock", fx: "exclaim"))
        XCTAssertEqual(d.directive(at: 3), Directive(pose: "lie_edge", face: "sad"))
        XCTAssertEqual(d.directive(at: 61), Directive(pose: "lie_edge"))
    }

    func testDoneCelebratesThenHappy() {
        let d = Director(now: 0)
        d.handle(.state(.done, note: nil), at: 0)
        XCTAssertEqual(d.directive(at: 1), Directive(pose: "celebrate", fx: "sparkle"))
        XCTAssertEqual(d.directive(at: 3), Directive(pose: "lie_edge", face: "happy"))
    }

    func testWaitingUserWavesThenSitsUntilSleep() {
        let d = Director(now: 0)
        d.handle(.state(.waitingUser, note: nil), at: 0)
        XCTAssertEqual(d.directive(at: 1), Directive(pose: "wave", fx: "question"))
        XCTAssertEqual(pose(d, 200), "sit_corner")
        XCTAssertEqual(d.directive(at: 301), Directive(pose: "sleep", fx: "zzz"))
    }

    func testStaleBusyFallsBackToIdle() {
        let d = Director(now: 0)
        d.handle(.state(.working, note: nil), at: 0)
        XCTAssertEqual(pose(d, 119), "work")
        XCTAssertEqual(pose(d, 121), "lie_edge")
    }

    func testIdleLadderSleeps() {
        let d = Director(now: 0)
        XCTAssertEqual(pose(d, 299), "lie_edge")
        XCTAssertEqual(d.directive(at: 301), Directive(pose: "sleep", fx: "zzz"))  // ≥ 1.5 s after the last pose change
    }

    func testShowOverridesForHoldThenReturns() {
        let d = Director(now: 0)
        d.handle(.state(.working, note: nil), at: 0)
        d.handle(.show(ShowRequest(pose: "point", at: .rect(Rect(x: 1, y: 2, w: 3, h: 4)), say: "here", holdS: 3)), at: 10)
        XCTAssertEqual(d.directive(at: 11),
                       Directive(pose: "point", say: "here", target: .rect(Rect(x: 1, y: 2, w: 3, h: 4))))
        XCTAssertEqual(pose(d, 13.5), "work")
    }

    func testShowWithoutPoseKeepsCurrentPose() {
        let d = Director(now: 0)
        d.handle(.state(.thinking, note: nil), at: 0)
        _ = d.directive(at: 0)
        d.handle(.show(ShowRequest(face: "happy", fx: "sparkle")), at: 1)
        XCTAssertEqual(d.directive(at: 1), Directive(pose: "think", face: "happy", fx: "sparkle"))
    }

    func testMinDwellDelaysStatePoseChanges() {
        let d = Director(now: 0)
        d.handle(.state(.thinking, note: nil), at: 0)
        XCTAssertEqual(pose(d, 0), "think")
        d.handle(.state(.working, note: nil), at: 0.5)
        XCTAssertEqual(pose(d, 0.5), "think")
        XCTAssertEqual(pose(d, 1.6), "work")
    }

    func testShowIgnoresMinDwell() {
        let d = Director(now: 0)
        d.handle(.state(.thinking, note: nil), at: 0)
        _ = d.directive(at: 0)
        d.handle(.show(ShowRequest(pose: "wave")), at: 0.2)
        XCTAssertEqual(pose(d, 0.2), "wave")
    }

    func testDwellHoldKeepsOnlyThePose() {
        let d = Director(now: 0)
        d.handle(.state(.thinking, note: nil), at: 0)
        d.handle(.show(ShowRequest(pose: "wave", say: "hi", holdS: 1)), at: 0)
        XCTAssertEqual(d.directive(at: 0).say, "hi")
        // show expired at 1.0, but the pose changed at 0 and minDwell is 1.5: pose held, say not
        XCTAssertEqual(d.directive(at: 1.2), Directive(pose: "wave"))
    }

    func testActivityPicksActionPose() {
        let d = Director(now: 0)
        d.handle(.state(.working, activity: "typing"), at: 0)
        XCTAssertEqual(pose(d, 0), "type")
        d.handle(.state(.working, activity: "reading"), at: 2)
        XCTAssertEqual(pose(d, 2), "read")
        d.handle(.state(.working, activity: "running"), at: 4)
        XCTAssertEqual(pose(d, 4), "tail_swipe")
        d.handle(.state(.working, activity: "juggling"), at: 6)
        XCTAssertEqual(pose(d, 6), "work")
        d.handle(.state(.thinking, activity: "browsing"), at: 8)
        XCTAssertEqual(pose(d, 8), "search")
    }
}
