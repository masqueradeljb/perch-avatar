/// Axis-aligned rectangle in CG space: top-left origin of the primary display, y down, points.
public struct Rect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public var maxX: Double { x + w }
    public var maxY: Double { y + h }
    public var area: Double { w * h }

    /// True when `r` lies inside this rect (half-point tolerance for float noise).
    public func contains(_ r: Rect) -> Bool {
        r.x >= x - 0.5 && r.y >= y - 0.5 && r.maxX <= maxX + 0.5 && r.maxY <= maxY + 0.5
    }

    public func intersectionArea(_ r: Rect) -> Double {
        let iw = min(maxX, r.maxX) - max(x, r.x)
        let ih = min(maxY, r.maxY) - max(y, r.y)
        return (iw > 0 && ih > 0) ? iw * ih : 0
    }
}

/// Converts a Vision bounding box (normalized, origin bottom-left) of an image that covers `frame`
/// into a CG-space screen rect (top-left origin).
public func visionRectToScreen(_ x: Double, _ y: Double, _ w: Double, _ h: Double, in frame: Rect) -> Rect {
    Rect(x: frame.x + x * frame.w, y: frame.y + (1 - y - h) * frame.h, w: w * frame.w, h: h * frame.h)
}
