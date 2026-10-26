import XCTest
@testable import AvatarCore

final class PlacementTests: XCTestCase {
    let usable = Rect(x: 0, y: 25, w: 1440, h: 800)
    let lie = PoseBox(w: 200, h: 200, contact: Contact(x: [0.1, 0.9], y: [0.7, 0.7]))
    let peek = PoseBox(w: 150, h: 200, contact: Contact(x: [0.8, 0.8], y: [0.2, 0.6]))
    let stand = PoseBox(w: 120, h: 200, contact: Contact(x: [0.3, 0.7], y: [0.98, 0.98]))

    let screen = Rect(x: 0, y: 0, w: 1440, h: 900)  // menu bar is y 0…25; usable starts at 25

    func input(_ window: Rect, order: [Edge] = Placer.defaultOrder, topPos: Double = 0.7,
               screen: Rect? = nil) -> PlacementInput {
        PlacementInput(window: window, usable: usable, screen: screen,
                       boxes: [.top: lie, .cornerLeft: lie, .cornerRight: lie, .side: peek, .floor: stand, .inset: stand],
                       order: order, topPos: topPos)
    }

    func assertRect(_ r: Rect?, _ e: Rect, file: StaticString = #filePath, line: UInt = #line) {
        guard let r else { return XCTFail("nil rect", file: file, line: line) }
        for (a, b) in [(r.x, e.x), (r.y, e.y), (r.w, e.w), (r.h, e.h)] {
            XCTAssertEqual(a, b, accuracy: 0.001, "\(r) != \(e)", file: file, line: line)
        }
    }

    // MARK: top

    func testTopRestsContactLineOnWindowTop() {
        let p = Placer.place(.top, input(Rect(x: 300, y: 300, w: 800, h: 400)))
        XCTAssertEqual(p?.edge, .top)
        XCTAssertEqual(p?.mirrored, false)
        // contact y 140 sits on window top 300 → frame y 160; contact center at 300+0.7*800 = 860 → x 760
        assertRect(p?.frame, Rect(x: 760, y: 160, w: 200, h: 200))
    }

    func testTopClampsContactInsideWindow() {
        let p = Placer.place(.top, input(Rect(x: 300, y: 300, w: 800, h: 400), topPos: 1.0))
        // contact end (x+180) may not pass window right edge 1100 → x 920
        assertRect(p?.frame, Rect(x: 920, y: 160, w: 200, h: 200))
    }

    func testTopFailsWhenWindowHugsMenuBar() {
        XCTAssertNil(Placer.place(.top, input(Rect(x: 300, y: 25, w: 800, h: 400))))
    }

    func testTopShrinksForNarrowWindowDownToMinimum() {
        // contact span 160: a 150-wide window takes scale 0.9 (144); 110 is below 0.75 (120)
        XCTAssertEqual(Placer.place(.top, input(Rect(x: 300, y: 300, w: 150, h: 300)))?.scale, 0.9)
        XCTAssertNil(Placer.place(.top, input(Rect(x: 300, y: 300, w: 110, h: 300))))
    }

    func testTopMayCoverMenuBar() {
        // needs 140 pt above the window top 150 → frame y 10 sits inside the menu bar
        let p = Placer.place(.top, input(Rect(x: 300, y: 150, w: 800, h: 400), screen: screen))
        XCTAssertEqual(p?.scale, 1)
        assertRect(p?.frame, Rect(x: 760, y: 10, w: 200, h: 200))
    }

    func testTopShrinksBeforeGivingUp() {
        // 130 pt above the window < 140 → scale 0.9: 180×180, contact y 126, contact span 18…162
        let p = Placer.place(.top, input(Rect(x: 300, y: 130, w: 800, h: 400), screen: screen))
        XCTAssertEqual(p?.scale, 0.9)
        assertRect(p?.frame, Rect(x: 770, y: 4, w: 180, h: 180))
    }

    func testTopNeverShrinksBelowMinimum() {
        // flush with the menu bar: 25 pt available, even 0.75 needs 105
        XCTAssertNil(Placer.place(.top, input(Rect(x: 300, y: 25, w: 800, h: 400), screen: screen)))
    }

    // MARK: corners

    func testCornerRightIsMirroredAndOverhangs() {
        let p = Placer.place(.cornerRight, input(Rect(x: 300, y: 300, w: 800, h: 400)))
        XCTAssertEqual(p?.edge, .cornerRight)
        XCTAssertEqual(p?.mirrored, true)
        // mirrored contact span 20…180; 30% of 160 = 48 hangs past right edge 1100 → x = 1100-180+48
        assertRect(p?.frame, Rect(x: 968, y: 160, w: 200, h: 200))
    }

    func testCornerLeftFailsOffScreen() {
        XCTAssertNil(Placer.place(.cornerLeft, input(Rect(x: 0, y: 300, w: 800, h: 400))))
    }

    // MARK: sides

    func testSidePrefersRoomierRightSideMirrored() {
        // hugs menu bar; left room 300, right room 340
        let p = Placer.place(.side, input(Rect(x: 300, y: 25, w: 800, h: 400)))
        XCTAssertEqual(p?.edge, .side)
        XCTAssertEqual(p?.mirrored, true)
        // mirrored grip x = 0.2*150 = 30 on edge 1100; grip center 80 at 25+0.3*400 = 145 → y 65
        assertRect(p?.frame, Rect(x: 1070, y: 65, w: 150, h: 200))
    }

    func testSidePrefersRoomierLeftSide() {
        let p = Placer.place(.side, input(Rect(x: 700, y: 25, w: 700, h: 400)))
        XCTAssertEqual(p?.mirrored, false)
        assertRect(p?.frame, Rect(x: 580, y: 65, w: 150, h: 200))
    }

    func testSideHonorsPreferredSide() {
        // right has more room (340 > 300), but the caller asked for the left
        var i = input(Rect(x: 300, y: 25, w: 800, h: 400))
        i.preferRight = false
        let p = Placer.place(.side, i)
        XCTAssertEqual(p?.mirrored, false)
        i.preferRight = true
        XCTAssertEqual(Placer.place(.side, i)?.mirrored, true)
    }

    func testSideFailsWithNoRoomEitherSide() {
        XCTAssertNil(Placer.place(.side, input(usable)))
    }

    // MARK: floor / inset / resolve

    func testFloorStandsOnDockRightOfWindow() {
        let p = Placer.place(.floor, input(Rect(x: 300, y: 100, w: 600, h: 500)))
        XCTAssertEqual(p?.edge, .floor)
        XCTAssertEqual(p?.mirrored, true)
        // feet (196) on usable bottom 825 → y 629; just right of window → x 900
        assertRect(p?.frame, Rect(x: 900, y: 629, w: 120, h: 200))
    }

    func testFloorFailsWhenItWouldCoverMaximizedWindow() {
        XCTAssertNil(Placer.place(.floor, input(usable)))
    }

    func testResolvePicksTopForOrdinaryWindow() {
        XCTAssertEqual(Placer.resolve(input(Rect(x: 300, y: 300, w: 800, h: 400)))?.edge, .top)
    }

    func testResolveFallsBackToSideWhenWindowHugsMenuBar() {
        XCTAssertEqual(Placer.resolve(input(Rect(x: 300, y: 25, w: 800, h: 400)))?.edge, .side)
    }

    func testResolveMaximizedWindowGoesToSmallInset() {
        let p = Placer.resolve(input(usable))
        XCTAssertEqual(p?.edge, .inset)
        XCTAssertEqual(p?.scale, 0.6)
        // stand scaled to 72×120, feet 117.6 on 825, 16 pt from right edge
        assertRect(p?.frame, Rect(x: 1352, y: 707.4, w: 72, h: 120))
    }

    func testForcedOrderIsRespected() {
        XCTAssertEqual(Placer.resolve(input(Rect(x: 300, y: 300, w: 800, h: 400), order: [.cornerRight]))?.edge, .cornerRight)
    }

    // MARK: pointing

    let pointer = PoseBox(w: 200, h: 200, contact: Contact(x: [0.3, 0.7], y: [0.97, 0.97]))

    func testPointAtPutsTipOnRectsLeftEdge() {
        let p = Placer.pointAt(Rect(x: 800, y: 400, w: 100, h: 40), box: pointer, tip: [0.95, 0.15], usable: usable)
        XCTAssertEqual(p?.edge, .pointing)
        XCTAssertEqual(p?.mirrored, false)
        // tip (190, 30) lands on (800, 420)
        assertRect(p?.frame, Rect(x: 610, y: 390, w: 200, h: 200))
    }

    func testPointAtMirrorsWhenNoRoomOnTheLeft() {
        let p = Placer.pointAt(Rect(x: 10, y: 400, w: 100, h: 40), box: pointer, tip: [0.95, 0.15], usable: usable)
        XCTAssertEqual(p?.mirrored, true)
        // mirrored tip x = 0.05 * 200 = 10 lands on the rect's right edge 110
        assertRect(p?.frame, Rect(x: 100, y: 390, w: 200, h: 200))
    }
}
