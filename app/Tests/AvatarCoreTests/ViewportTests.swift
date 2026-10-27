import XCTest
@testable import AvatarCore

final class ViewportTests: XCTestCase {
    func testToScreenOffsetsByWindowOriginAndTopInset() {
        let p = Viewport.toScreen(x: 274, y: 402, window: Rect(x: 100, y: 50, w: 1200, h: 800), topInset: 87)
        XCTAssertEqual(p.x, 374)
        XCTAssertEqual(p.y, 539)
    }

    func testCustomInsetAndDefault() {
        XCTAssertEqual(Viewport.defaultTopInset, 87)
        let p = Viewport.toScreen(x: 0, y: 0, window: Rect(x: 0, y: 25, w: 800, h: 600), topInset: 115)
        XCTAssertEqual(p.x, 0)
        XCTAssertEqual(p.y, 140)
    }
}
