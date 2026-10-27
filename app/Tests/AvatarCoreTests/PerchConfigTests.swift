import XCTest
@testable import AvatarCore

final class PerchConfigTests: XCTestCase {
    func testIgnoreApps() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertEqual(PerchConfig.ignoreApps(home: home), [])
        try Data(#"{"pack":"kuro","ignoreApps":["Karabiner-Elements","BetterTouchTool"]}"#.utf8)
            .write(to: home.appendingPathComponent("config.json"))
        XCTAssertEqual(PerchConfig.ignoreApps(home: home), ["karabiner-elements", "bettertouchtool"])
    }
}
