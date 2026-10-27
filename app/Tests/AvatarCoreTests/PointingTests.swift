import XCTest
@testable import AvatarCore

final class PointingTests: XCTestCase {
    let usable = Rect(x: 0, y: 0, w: 1000, h: 1000)
    let contact = Contact(x: [0.2, 0.8], y: [0.95, 0.95])
    var up: PointCandidate { PointCandidate(name: "tap", box: PoseBox(w: 100, h: 100, contact: contact), tip: [0.9, 0.1]) }
    var down: PointCandidate { PointCandidate(name: "tap_down", box: PoseBox(w: 100, h: 100, contact: contact), tip: [0.9, 0.9]) }
    let target = Rect(x: 500, y: 500, w: 1, h: 1)

    func testPoseFamilyDecodes() throws {
        let pose = try JSONDecoder().decode(Pose.self, from: Data(#"{"anchor":"floor","image":"p.png","family":"point"}"#.utf8))
        XCTAssertEqual(pose.family, "point")
    }

    func testWithoutCurrentFrameFirstFittingWins() {
        let r = Placer.pickPointing(target, candidates: [up, down], usable: usable, near: nil)
        XCTAssertEqual(r?.name, "tap")
        XCTAssertEqual(r?.placement.mirrored, false)
        XCTAssertEqual(r?.placement.frame, Rect(x: 410, y: 490.5, w: 100, h: 100))
    }

    func testNearestToCurrentFrameWins() {
        // body above the target → the tail reaches down
        XCTAssertEqual(Placer.pickPointing(target, candidates: [up, down], usable: usable,
                                           near: Rect(x: 410, y: 400, w: 100, h: 100))?.name, "tap_down")
        // body below the target → the tail reaches up
        XCTAssertEqual(Placer.pickPointing(target, candidates: [up, down], usable: usable,
                                           near: Rect(x: 410, y: 540, w: 100, h: 100))?.name, "tap")
    }

    func testMirrorsWhenTheLeftSideDoesNotFit() {
        let r = Placer.pickPointing(Rect(x: 30, y: 500, w: 1, h: 1), candidates: [up], usable: usable, near: nil)
        XCTAssertEqual(r?.placement.mirrored, true)
    }

    func testNilWhenNothingFits() {
        XCTAssertNil(Placer.pickPointing(target, candidates: [up], usable: Rect(x: 0, y: 0, w: 50, h: 50), near: nil))
        XCTAssertNil(Placer.pickPointing(target, candidates: [], usable: usable, near: nil))
    }
}
