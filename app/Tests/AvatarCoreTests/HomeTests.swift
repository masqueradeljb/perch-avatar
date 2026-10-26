import XCTest
@testable import AvatarCore

final class HomeTests: XCTestCase {
    // avatar CLI 900 → sh 800 → claude 700 → zsh 600 → Terminal 500 (has windows) → launchd 1
    let parents: [Int32: Int32] = [900: 800, 800: 700, 700: 600, 600: 500, 500: 1]

    func testWalksUpToFirstProcessWithAWindow() {
        XCTAssertEqual(resolveHome(pid: 900, parent: { self.parents[$0] }, hasWindow: { $0 == 500 }), 500)
    }

    func testSenderItselfCanBeHome() {
        XCTAssertEqual(resolveHome(pid: 500, parent: { self.parents[$0] }, hasWindow: { $0 == 500 }), 500)
    }

    func testNilWhenNoAncestorHasAWindow() {
        XCTAssertNil(resolveHome(pid: 900, parent: { self.parents[$0] }, hasWindow: { _ in false }))
    }

    func testStopsOnCycles() {
        XCTAssertNil(resolveHome(pid: 2, parent: { $0 == 2 ? 3 : 2 }, hasWindow: { _ in false }))
    }
}
