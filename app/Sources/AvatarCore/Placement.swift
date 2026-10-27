import Foundation

/// Where the character is attached relative to the target window.
public enum Edge: String, CaseIterable {
    case top, cornerLeft, cornerRight, side, floor, inset, pointing
}

/// A pose's on-screen size (points) and its normalized contact line, as drawn (facing right).
public struct PoseBox: Equatable {
    public var w: Double
    public var h: Double
    public var contact: Contact

    public init(w: Double, h: Double, contact: Contact) {
        self.w = w
        self.h = h
        self.contact = contact
    }

    /// Same box flipped horizontally (character faces left).
    public var mirrored: PoseBox {
        PoseBox(w: w, h: h, contact: Contact(x: [1 - contact.x[1], 1 - contact.x[0]], y: contact.y))
    }

    public func scaled(_ s: Double) -> PoseBox { PoseBox(w: w * s, h: h * s, contact: contact) }

    var cx0: Double { contact.x[0] * w }
    var cx1: Double { contact.x[1] * w }
    var cy0: Double { contact.y[0] * h }
    var cy1: Double { contact.y[1] * h }
}

public struct Placement: Equatable {
    public var edge: Edge
    public var frame: Rect
    public var mirrored: Bool
    public var scale: Double
}

/// A pose that can point: its box and normalized hotspot tip (as drawn, facing right).
public struct PointCandidate: Equatable {
    public var name: String
    public var box: PoseBox
    public var tip: [Double]

    public init(name: String, box: PoseBox, tip: [Double]) {
        self.name = name
        self.box = box
        self.tip = tip
    }
}

public struct PlacementInput {
    public var window: Rect
    public var usable: Rect
    /// Full display frame. When given, top/corner poses may rise into the menu bar (above `usable`).
    public var screen: Rect?
    public var boxes: [Edge: PoseBox]
    public var order: [Edge]
    /// 0–1 along the window's top edge where the contact center should sit.
    public var topPos: Double
    /// 0–1 down the window's side where the grip center should sit.
    public var sidePos: Double
    /// Preferred side for `.side` poses: true = right, false = left, nil = whichever has more room.
    public var preferRight: Bool?

    public init(window: Rect, usable: Rect, screen: Rect? = nil, boxes: [Edge: PoseBox], order: [Edge],
                topPos: Double = 0.7, sidePos: Double = 0.3, preferRight: Bool? = nil) {
        self.window = window
        self.usable = usable
        self.screen = screen
        self.boxes = boxes
        self.order = order
        self.topPos = topPos
        self.sidePos = sidePos
        self.preferRight = preferRight
    }

    /// Area a pose perched on the window top may occupy: usable area extended up over the menu bar.
    var perchArea: Rect {
        let top = min(screen?.y ?? usable.y, usable.y)
        return Rect(x: usable.x, y: top, w: usable.w, h: usable.maxY - top)
    }
}

public enum Placer {
    public static let defaultOrder: [Edge] = [.top, .side, .floor]

    /// First edge in `order` that fits; falls back to a small inset. Nil only if no inset/floor box exists.
    public static func resolve(_ i: PlacementInput) -> Placement? {
        for edge in i.order {
            if let p = place(edge, i) { return p }
        }
        return inset(i)
    }

    /// Places a pointing pose so its hotspot touches the middle of the rect's left side
    /// (facing right), or its right side mirrored when there is no room on the left.
    public static func pointAt(_ rect: Rect, box: PoseBox, tip: [Double], usable: Rect) -> Placement? {
        for mirrored in [false, true] {
            let frame = pointFrame(rect, box: box, tip: tip, mirrored: mirrored)
            if usable.contains(frame) { return Placement(edge: .pointing, frame: frame, mirrored: mirrored, scale: 1) }
        }
        return nil
    }

    /// Frame that puts the hotspot on the middle of the rect's left side (right side when mirrored).
    public static func pointFrame(_ rect: Rect, box: PoseBox, tip: [Double], mirrored: Bool) -> Rect {
        let tipX = (mirrored ? 1 - tip[0] : tip[0]) * box.w
        let anchorX = mirrored ? rect.maxX : rect.x
        return Rect(x: anchorX - tipX, y: rect.y + rect.h / 2 - tip[1] * box.h, w: box.w, h: box.h)
    }

    /// Picks the variant and facing whose frame fits `usable` and lies closest to `current`, so a
    /// nearby target swings the tail instead of moving the body. Without `current`: the first that fits.
    public static func pickPointing(_ rect: Rect, candidates: [PointCandidate], usable: Rect,
                                    near current: Rect?) -> (name: String, placement: Placement)? {
        var best: (name: String, placement: Placement, distance: Double)?
        for c in candidates {
            for mirrored in [false, true] {
                let frame = pointFrame(rect, box: c.box, tip: c.tip, mirrored: mirrored)
                guard usable.contains(frame) else { continue }
                let p = Placement(edge: .pointing, frame: frame, mirrored: mirrored, scale: 1)
                guard let current else { return (c.name, p) }
                let distance = hypot(frame.x + frame.w / 2 - current.x - current.w / 2,
                                     frame.y + frame.h / 2 - current.y - current.h / 2)
                if best == nil || distance < best!.distance { best = (c.name, p, distance) }
            }
        }
        return best.map { ($0.name, $0.placement) }
    }

    static let cornerOverhang = 0.3
    static let floorMaxOverlap = 0.3
    static let insetScale = 0.6
    static let insetMargin = 16.0
    /// Top/corner poses shrink step by step before giving up; never below the last value.
    static let perchScales = [1.0, 0.9, 0.8, 0.75]

    static func place(_ edge: Edge, _ i: PlacementInput) -> Placement? {
        guard let box = i.boxes[edge] else { return nil }
        switch edge {
        case .top: return top(box, i)
        case .cornerLeft: return corner(box, i, right: false)
        case .cornerRight: return corner(box, i, right: true)
        case .side: return side(box, i)
        case .floor: return floor(box, i)
        case .inset: return inset(i)
        case .pointing: return nil  // needs a target rect; see pointAt
        }
    }

    /// Sits on a top corner, facing into the window, with part of the contact hanging past the edge.
    static func corner(_ box: PoseBox, _ i: PlacementInput, right: Bool) -> Placement? {
        let w = i.window
        for s in perchScales {
            let b = (right ? box.mirrored : box).scaled(s)
            let overhang = cornerOverhang * (b.cx1 - b.cx0)
            let fx = right ? w.maxX - b.cx1 + overhang : w.x - b.cx0 - overhang
            let frame = Rect(x: fx, y: w.y - b.cy0, w: b.w, h: b.h)
            if i.perchArea.contains(frame) {
                return Placement(edge: right ? .cornerRight : .cornerLeft, frame: frame, mirrored: right, scale: s)
            }
        }
        return nil
    }

    /// Grips a side edge from outside the window, facing in. Tries the preferred side first (default: the roomier one).
    static func side(_ box: PoseBox, _ i: PlacementInput) -> Placement? {
        let w = i.window, u = i.usable
        let rightFirst = i.preferRight ?? ((u.maxX - w.maxX) >= (w.x - u.x))
        for right in rightFirst ? [true, false] : [false, true] {
            let b = right ? box.mirrored : box
            let fx = (right ? w.maxX : w.x) - b.cx0
            let lo = max(w.y - b.cy0, u.y)
            let hi = min(w.maxY - b.cy1, u.maxY - b.h)
            guard lo <= hi else { continue }
            let want = w.y + i.sidePos * w.h - (b.cy0 + b.cy1) / 2
            let frame = Rect(x: fx, y: min(max(want, lo), hi), w: b.w, h: b.h)
            if u.contains(frame) { return Placement(edge: .side, frame: frame, mirrored: right, scale: 1) }
        }
        return nil
    }

    /// Stands on the bottom of the usable area (top of the Dock) beside the window, facing it.
    static func floor(_ box: PoseBox, _ i: PlacementInput) -> Placement? {
        let w = i.window, u = i.usable
        let fy = u.maxY - box.cy0
        for (fx, mirrored) in [(w.maxX, true), (w.x - box.w, false)] {
            let frame = Rect(x: fx, y: fy, w: box.w, h: box.h)
            let onScreen = frame.x >= u.x && frame.maxX <= u.maxX && frame.y >= u.y
            if onScreen && frame.intersectionArea(w) <= floorMaxOverlap * frame.area {
                return Placement(edge: .floor, frame: frame, mirrored: mirrored, scale: 1)
            }
        }
        return nil
    }

    /// Last resort: shrunk, standing in the bottom-right corner of the usable area.
    static func inset(_ i: PlacementInput) -> Placement? {
        guard let box = (i.boxes[.inset] ?? i.boxes[.floor])?.scaled(insetScale) else { return nil }
        let u = i.usable
        let frame = Rect(x: u.maxX - box.w - insetMargin, y: u.maxY - box.cy0, w: box.w, h: box.h)
        return Placement(edge: .inset, frame: frame, mirrored: true, scale: insetScale)
    }

    /// Contact line rests on the window's top edge; contact span stays within the window.
    /// Shrinks through `perchScales` until it fits; the pose may rise into the menu bar.
    static func top(_ box: PoseBox, _ i: PlacementInput) -> Placement? {
        let w = i.window, area = i.perchArea
        for s in perchScales {
            let b = box.scaled(s)
            guard w.w >= b.cx1 - b.cx0 else { continue }
            let lo = max(w.x - b.cx0, area.x)
            let hi = min(w.maxX - b.cx1, area.maxX - b.w)
            guard lo <= hi else { continue }
            let want = w.x + i.topPos * w.w - (b.cx0 + b.cx1) / 2
            let frame = Rect(x: min(max(want, lo), hi), y: w.y - b.cy0, w: b.w, h: b.h)
            if area.contains(frame) { return Placement(edge: .top, frame: frame, mirrored: false, scale: s) }
        }
        return nil
    }
}
