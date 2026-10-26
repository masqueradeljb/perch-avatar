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
