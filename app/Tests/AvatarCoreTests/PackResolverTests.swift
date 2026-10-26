import XCTest
@testable import AvatarCore

final class PackResolverTests: XCTestCase {
    var root: URL!
    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("perch-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func makePack(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("pack.json").path, contents: Data("{}".utf8))
    }

    func testExplicitWins() {
        let r = PackResolver.resolve(explicit: "/x/y", home: root, bundled: nil)
        XCTAssertEqual(r?.path, "/x/y")
    }

    func testConfiguredPackBeforeBundled() throws {
        makePack(root.appendingPathComponent("packs/mine"))
        try Data(#"{"pack":"mine"}"#.utf8).write(to: root.appendingPathComponent("config.json"))
        let bundled = root.appendingPathComponent("bundled")
        makePack(bundled)
        XCTAssertEqual(PackResolver.resolve(explicit: nil, home: root, bundled: bundled)?.lastPathComponent, "mine")
    }

    func testConfiguredButMissingFallsBackToBundled() throws {
        try Data(#"{"pack":"ghost"}"#.utf8).write(to: root.appendingPathComponent("config.json"))
        let bundled = root.appendingPathComponent("bundled")
        makePack(bundled)
        XCTAssertEqual(PackResolver.resolve(explicit: nil, home: root, bundled: bundled), bundled)
    }

    func testRejectsTraversalId() throws {
        try Data(#"{"pack":"../evil"}"#.utf8).write(to: root.appendingPathComponent("config.json"))
        XCTAssertNil(PackResolver.resolve(explicit: nil, home: root, bundled: nil))
    }

    func testNothingFound() {
        XCTAssertNil(PackResolver.resolve(explicit: nil, home: root, bundled: root.appendingPathComponent("nope")))
    }
}
