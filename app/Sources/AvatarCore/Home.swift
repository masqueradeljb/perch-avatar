/// First process, starting at `pid` and walking up its parents, that owns an on-screen window.
/// A hook or MCP server is a descendant of the terminal / desktop app the agent runs in, so this
/// finds the agent's own window without configuration. Gives up after 32 steps (cycles, launchd).
public func resolveHome(pid: Int32, parent: (Int32) -> Int32?, hasWindow: (Int32) -> Bool) -> Int32? {
    var current: Int32? = pid
    for _ in 0..<32 {
        guard let p = current, p > 1 else { return nil }
        if hasWindow(p) { return p }
        current = parent(p)
    }
    return nil
}
