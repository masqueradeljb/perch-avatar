import Foundation

/// Optional settings in `~/.perch/config.json` besides `pack` (see PackResolver).
public enum PerchConfig {
    /// Lowercased names of apps whose posted input is never the agent's (key remappers, remote control).
    public static func ignoreApps(home: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("config.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = json["ignoreApps"] as? [String] else { return [] }
        return Set(apps.map { $0.lowercased() })
    }
}
