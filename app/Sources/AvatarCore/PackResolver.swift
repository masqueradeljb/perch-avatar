import Foundation

/// Finds the pack to load: `--pack` → `~/.perch/packs/<id>` (id from `~/.perch/config.json`) → bundled pack.
public enum PackResolver {
    public static let bundledId = "kuro"

    public static func isPack(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path)
    }

    /// `home` is the Perch config directory (`~/.perch`); `bundled` is `Resources/packs/kuro` when running from an app bundle.
    public static func resolve(explicit: String?, home: URL, bundled: URL?) -> URL? {
        if let explicit { return URL(fileURLWithPath: explicit) }
        if let id = configuredId(home: home) {
            let dir = home.appendingPathComponent("packs").appendingPathComponent(id)
            if isPack(dir) { return dir }
        }
        if let bundled, isPack(bundled) { return bundled }
        return nil
    }

    static func configuredId(home: URL) -> String? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("config.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["pack"] as? String, !id.isEmpty,
              !id.contains("/"), !id.contains("..") else { return nil }
        return id
    }
}

/// A pack the user can switch to.
public struct PackInfo: Equatable {
    public let id: String
    public let name: String
    public let dir: URL
    public init(id: String, name: String, dir: URL) {
        self.id = id
        self.name = name
        self.dir = dir
    }
}

extension PackResolver {
    private struct Header: Decodable {
        let id: String?
        let name: String?
    }

    /// The name in `dir/pack.json` (falling back to its id); nil when the file is missing or unreadable.
    static func header(_ dir: URL) -> (id: String, name: String)? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("pack.json")),
              let h = try? JSONDecoder().decode(Header.self, from: data),
              let label = h.name ?? h.id, !label.isEmpty else { return nil }
        return (h.id ?? label, label)
    }

    /// Bundled pack first, then each `~/.perch/packs/<id>` holding a decodable pack.json (sorted by id;
    /// a user pack with the bundled id hides the bundled one).
    public static func available(home: URL, bundled: URL?) -> [PackInfo] {
        let packs = home.appendingPathComponent("packs")
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: packs.path)) ?? [])
            .filter { !$0.hasPrefix(".") }.sorted()
        let user: [PackInfo] = ids.compactMap { id in
            let dir = packs.appendingPathComponent(id)
            return header(dir).map { PackInfo(id: id, name: $0.name, dir: dir) }
        }
        guard let bundled, !user.contains(where: { $0.id == bundledId }),
              let h = header(bundled) else { return user }
        return [PackInfo(id: bundledId, name: h.name, dir: bundled)] + user
    }

    /// Writes `{"pack": id}` into config.json, keeping its other keys (creates the file/dir if needed).
    public static func select(_ id: String, home: URL) throws {
        let url = home.appendingPathComponent("config.json")
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { json = existing }
        json["pack"] = id
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
