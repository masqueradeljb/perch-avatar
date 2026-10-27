/// Raw input another process posted (computer use), in CG screen points.
public enum InputEvent: Equatable {
    case click(x: Double, y: Double)
    /// `dy` as the scroll-wheel event reports it: > 0 scrolls up.
    case scroll(x: Double, y: Double, dy: Double)
    /// A key press; which key is never recorded.
    case key
}

/// Turns posted input into acts: every click, the first scroll of a burst (a new burst after a
/// pause or a direction flip), and the first key of a typing burst, placed at a recent click.
public final class ActCoalescer {
    public static let scrollGap = 0.3
    public static let keyGap = 1.0
    /// Typing is placed at the last click this recent (likely the field being typed into).
    public static let clickMemory = 5.0

    private var lastClick: (x: Double, y: Double, at: Double)?
    private var lastScroll: (dir: ScrollDir, at: Double)?
    private var lastKeyAt = -Double.infinity

    public init() {}

    public func feed(_ e: InputEvent, at t: Double) -> ActRequest? {
        switch e {
        case let .click(x, y):
            lastClick = (x, y, t)
            return ActRequest(action: .click, x: x, y: y, source: "input")
        case let .scroll(x, y, dy):
            guard dy != 0 else { return nil }
            let dir: ScrollDir = dy > 0 ? .up : .down
            defer { lastScroll = (dir, t) }
            if let s = lastScroll, s.dir == dir, t - s.at < Self.scrollGap { return nil }
            return ActRequest(action: .scroll, x: x, y: y, dir: dir, source: "input")
        case .key:
            defer { lastKeyAt = t }
            guard t - lastKeyAt >= Self.keyGap else { return nil }
            if let c = lastClick, t - c.at < Self.clickMemory {
                return ActRequest(action: .type, x: c.x, y: c.y, source: "input")
            }
            return ActRequest(action: .type, source: "input")
        }
    }
}
