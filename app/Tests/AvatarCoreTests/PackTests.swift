import XCTest
@testable import AvatarCore

final class PackTests: XCTestCase {
    private func json(lieContactX: String = "[0.1, 0.9]") -> Data {
        """
        {"spec": 1, "id": "m0", "name": "M0", "poses": {
          "lie_edge": {"anchor": "edge_top", "image": "poses/lie_edge.png", "facing": "right",
                       "contact": {"x": \(lieContactX), "y": [0.7, 0.7]}},
          "run": {"anchor": "free", "image": "poses/run.png"}
        }}
        """.data(using: .utf8)!
    }

    func testDecodesPosesAndIgnoresUnknownKeys() throws {
        let pack = try Pack.decode(json(), required: ["lie_edge"])
        XCTAssertEqual(pack.id, "m0")
        XCTAssertEqual(pack.poses["lie_edge"]?.anchor, .edgeTop)
        XCTAssertEqual(pack.poses["lie_edge"]?.contact, Contact(x: [0.1, 0.9], y: [0.7, 0.7]))
        XCTAssertNil(pack.poses["run"]?.contact)
    }

    func testMissingRequiredPosesAreListedSorted() {
        XCTAssertThrowsError(try Pack.decode(json(), required: ["lie_edge", "stand", "peek_side"])) { error in
            XCTAssertEqual(error as? PackError, .missingPoses(["peek_side", "stand"]))
        }
    }

    func testRejectsInvertedContact() {
        XCTAssertThrowsError(try Pack.decode(json(lieContactX: "[0.9, 0.1]"), required: [])) { error in
            XCTAssertEqual(error as? PackError, .badContact("lie_edge"))
        }
    }

    func testDecodesFacesHotspotExtrasAndScale() throws {
        let data = """
        {"spec": 1, "id": "k", "name": "K", "poses": {
          "point": {"anchor": "floor", "image": "poses/point.png", "scale": 0.9,
                    "contact": {"x": [0.3, 0.8], "y": [0.97, 0.97]}, "hotspot": {"tip": [0.98, 0.16]}},
          "stand": {"anchor": "floor", "image": "poses/stand.png",
                    "contact": {"x": [0.2, 0.8], "y": [0.95, 0.95]}, "faces": {"happy": "poses/stand.happy.png"}}
        }, "extras": {
          "lie_low": {"anchor": "edge_top", "image": "poses/lie_low.png", "contact": {"x": [0.1, 0.9], "y": [0.3, 0.3]}},
          "stand": {"anchor": "floor", "image": "poses/other.png", "contact": {"x": [0.1, 0.9], "y": [0.9, 0.9]}}
        }}
        """.data(using: .utf8)!
        let pack = try Pack.decode(data, required: [])
        XCTAssertEqual(pack.poses["point"]?.hotspot?.tip, [0.98, 0.16])
        XCTAssertEqual(pack.poses["point"]?.scale, 0.9)
        XCTAssertEqual(pack.poses["stand"]?.faces?["happy"], "poses/stand.happy.png")
        XCTAssertEqual(pack.allPoses["lie_low"]?.image, "poses/lie_low.png")
        XCTAssertEqual(pack.allPoses["stand"]?.image, "poses/stand.png")  // core wins over extras
    }

    func testRejectsBadContactInExtras() {
        let data = """
        {"spec": 1, "id": "k", "name": "K", "poses": {},
         "extras": {"lie_low": {"anchor": "edge_top", "image": "x.png", "contact": {"x": [0.9, 0.1], "y": [0.3, 0.3]}}}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try Pack.decode(data, required: [])) { error in
            XCTAssertEqual(error as? PackError, .badContact("lie_low"))
        }
    }

    func testDecodesFramesAndFps() throws {
        let data = """
        {"spec": 1, "id": "k", "name": "K", "poses": {
          "type": {"anchor": "floor", "image": "poses/a.png", "frames": ["poses/a.png", "poses/a.f2.png"], "fps": 5,
                   "contact": {"x": [0.2, 0.8], "y": [0.95, 0.95]}},
          "stand": {"anchor": "floor", "image": "poses/s.png", "contact": {"x": [0.2, 0.8], "y": [0.95, 0.95]}}
        }}
        """.data(using: .utf8)!
        let pack = try Pack.decode(data, required: [])
        XCTAssertEqual(pack.poses["type"]?.frames?.count, 2)
        XCTAssertEqual(pack.poses["type"]?.fps, 5)
        XCTAssertNil(pack.poses["stand"]?.frames)
    }
}
