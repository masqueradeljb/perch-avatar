import Foundation

/// Optional settings in `~/.perch/config.json` besides `pack` (see PackResolver).
public enum PerchConfig {
    /// Lowercased names of apps whose posted input is never the agent's (key remappers, remote control).
    public static func ignoreApps(home: URL) -> Set<String> {
        guard let apps = json(home: home)?["ignoreApps"] as? [String] else { return [] }
        return Set(apps.map { $0.lowercased() })
    }

    /// Points between a browser window's top edge and its page content (`browserTopInset`, e.g. 115 with
    /// Chrome's bookmarks bar). nil = not set; callers fall back to `Viewport.defaultTopInset`.
    public static func browserTopInset(home: URL) -> Double? {
        (json(home: home)?["browserTopInset"] as? NSNumber)?.doubleValue
    }

    private static func json(home: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("config.json")) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
