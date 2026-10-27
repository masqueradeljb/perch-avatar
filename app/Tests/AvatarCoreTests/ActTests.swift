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
}
