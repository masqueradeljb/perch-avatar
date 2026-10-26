import XCTest
@testable import AvatarCore

final class ProtocolTests: XCTestCase {
    func decode(_ s: String) throws -> Request {
        try JSONDecoder().decode(Request.self, from: s.data(using: .utf8)!)
    }

    func testState() throws {
        XCTAssertEqual(try decode(#"{"type":"state","state":"waiting_user","note":"approve?"}"#),
                       .state(.waitingUser, note: "approve?"))
    }

    func testStateWithActivity() throws {
        XCTAssertEqual(try decode(#"{"type":"state","state":"working","activity":"typing"}"#),
                       .state(.working, note: nil, activity: "typing"))
    }

    func testShowWithTextTarget() throws {
        XCTAssertEqual(try decode(#"{"type":"show","at":{"text":"Black cat","window":"Google Chrome"}}"#),
                       .show(ShowRequest(at: .text("Black cat", app: "Google Chrome"))))
        XCTAssertEqual(try decode(#"{"type":"show","at":{"text":"Black cat"}}"#),
                       .show(ShowRequest(at: .text("Black cat", app: nil))))
        // text wins over rect/window
        XCTAssertEqual(try decode(#"{"type":"show","at":{"text":"x","rect":[1,2,3,4],"window":"Safari"}}"#),
                       .show(ShowRequest(at: .text("x", app: "Safari"))))
    }

    func testTextTargetRoundTrips() throws {
        for t in [Target.text("Black cat", app: "Google Chrome"), .text("hi", app: nil)] {
            let data = try JSONEncoder().encode(t)
            XCTAssertEqual(try JSONDecoder().decode(Target.self, from: data), t)
        }
    }

    func testShowWithRect() throws {
        XCTAssertEqual(try decode(#"{"type":"show","pose":"point","at":{"rect":[1,2,3,4]},"say":"hi","hold_s":2}"#),
                       .show(ShowRequest(pose: "point", at: .rect(Rect(x: 1, y: 2, w: 3, h: 4)), say: "hi", holdS: 2)))
    }

    func testShowWithWindowTarget() throws {
        XCTAssertEqual(try decode(#"{"type":"show","at":{"window":"Safari","edge":"top","pos":0.3}}"#),
                       .show(ShowRequest(at: .window(app: "Safari", edge: "top", pos: 0.3))))
        XCTAssertEqual(try decode(#"{"type":"show","at":{"window":"focused"}}"#),
                       .show(ShowRequest(at: .window(app: nil, edge: nil, pos: nil))))
    }

    func testTargetsAndErrors() throws {
        XCTAssertEqual(try decode(#"{"type":"targets"}"#), .targets)
        XCTAssertThrowsError(try decode(#"{"type":"dance"}"#))
        XCTAssertThrowsError(try decode(#"{"type":"state","state":"sleepy"}"#))
        XCTAssertThrowsError(try decode(#"{"type":"show","at":{"rect":[1,2]}}"#))
    }

    func testResponseOmitsNils() throws {
        let ok = String(data: try JSONEncoder().encode(Response(ok: true)), encoding: .utf8)
        XCTAssertEqual(ok, #"{"ok":true}"#)
    }

    func envelope(_ s: String) throws -> Envelope {
        try JSONDecoder().decode(Envelope.self, from: s.data(using: .utf8)!)
    }

    func testEnvelopeCarriesPidAndWindow() throws {
        let e = try envelope(#"{"type":"state","state":"working","pid":4242,"window":"Google Chrome"}"#)
        XCTAssertEqual(e.request, .state(.working, note: nil))
        XCTAssertEqual(e.pid, 4242)
        XCTAssertEqual(e.window, "Google Chrome")
    }

    func testEnvelopeFieldsAreOptional() throws {
        let e = try envelope(#"{"type":"targets"}"#)
        XCTAssertEqual(e.request, .targets)
        XCTAssertNil(e.pid)
        XCTAssertNil(e.window)
    }
}
