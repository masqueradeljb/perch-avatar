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

    func writePack(_ dir: URL, id: String, name: String?) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = name.map { #"{"id":"\#(id)","name":"\#($0)","poses":{}}"# } ?? #"{"id":"\#(id)"}"#
        FileManager.default.createFile(atPath: dir.appendingPathComponent("pack.json").path, contents: Data(json.utf8))
    }

    func testAvailableListsBundledThenUserPacksSorted() {
        let bundled = root.appendingPathComponent("bundled")
        writePack(bundled, id: "kuro", name: "Kuro")
        writePack(root.appendingPathComponent("packs/zed"), id: "zed", name: "Zed")
        writePack(root.appendingPathComponent("packs/asuka"), id: "asuka", name: "Asuka")
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("packs/junk"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("packs/junk/pack.json").path, contents: Data("nope".utf8))
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("packs/empty"), withIntermediateDirectories: true)
        let list = PackResolver.available(home: root, bundled: bundled)
        XCTAssertEqual(list.map(\.id), [PackResolver.bundledId, "asuka", "zed"])
        XCTAssertEqual(list.map(\.name), ["Kuro", "Asuka", "Zed"])
        XCTAssertEqual(list[0].dir, bundled)
        XCTAssertEqual(list[1].dir.lastPathComponent, "asuka")
    }

    func testAvailableNameFallsBackToId() {
        writePack(root.appendingPathComponent("packs/noname"), id: "noname", name: nil)
        XCTAssertEqual(PackResolver.available(home: root, bundled: nil).map(\.name), ["noname"])
    }

    func testUserPackWithBundledIdHidesBundled() {
        let bundled = root.appendingPathComponent("bundled")
        writePack(bundled, id: "kuro", name: "Kuro")
        writePack(root.appendingPathComponent("packs/kuro"), id: "kuro", name: "My Kuro")
        let list = PackResolver.available(home: root, bundled: bundled)
        XCTAssertEqual(list.map(\.name), ["My Kuro"])
        XCTAssertEqual(list[0].dir.lastPathComponent, "kuro")
        XCTAssertNotEqual(list[0].dir, bundled)
    }

    func testSelectPreservesOtherKeys() throws {
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"pack":"old","ignoreApps":["Foo"]}"#.utf8).write(to: config)
        try PackResolver.select("asuka", home: root)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any]
        XCTAssertEqual(json?["pack"] as? String, "asuka")
        XCTAssertEqual(json?["ignoreApps"] as? [String], ["Foo"])
        XCTAssertEqual(PackResolver.configuredId(home: root), "asuka")
    }

    func testSelectCreatesConfigAndBundledIdResolvesToBundled() throws {
        let home = root.appendingPathComponent("fresh/.perch")
        try PackResolver.select(PackResolver.bundledId, home: home)
        XCTAssertEqual(PackResolver.configuredId(home: home), PackResolver.bundledId)
        let bundled = root.appendingPathComponent("bundled")
        makePack(bundled)
        XCTAssertEqual(PackResolver.resolve(explicit: nil, home: home, bundled: bundled), bundled)
    }
}
