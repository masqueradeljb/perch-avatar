import Foundation

public enum AnchorKind: String, Codable {
    case edgeTop = "edge_top"
    case corner
    case edgeSide = "edge_side"
    case floor
    case free
}

/// Where the body meets its support, normalized 0–1 with top-left origin.
/// Horizontal line: y[0] == y[1]. Vertical line (edge_side): x[0] == x[1].
public struct Contact: Codable, Equatable {
    public var x: [Double]
    public var y: [Double]

    public init(x: [Double], y: [Double]) {
        self.x = x
        self.y = y
    }

    var isValid: Bool {
        x.count == 2 && y.count == 2
            && (x + y).allSatisfy { (0...1).contains($0) }
            && x[0] <= x[1] && y[0] <= y[1]
    }
}

public struct Hotspot: Codable, Equatable {
    /// Normalized [x, y] of the part that points (Kuro: tail tip).
    public var tip: [Double]
}

public struct Pose: Codable, Equatable {
    public var anchor: AnchorKind
    public var image: String
    public var contact: Contact?
    public var hotspot: Hotspot?
    /// Face name → image path, drawn pixel-aligned with `image`.
    public var faces: [String: String]?
    /// Display-size multiplier so poses drawn at different sizes match on screen (default 1).
    public var scale: Double?
    /// Animation frames incl. the base image, pixel-aligned; cycled at `fps` (default 4).
    public var frames: [String]?
    public var fps: Double?
    /// Variant of another pose (e.g. "point"): same meaning, the hotspot reaching another way.
    public var family: String?
}

public struct Pack: Codable, Equatable {
    public var spec: Int
    public var id: String
    public var name: String
    public var poses: [String: Pose]
    public var extras: [String: Pose]?

    /// Core poses plus extras; a core pose wins over an extra with the same name.
    public var allPoses: [String: Pose] {
        (extras ?? [:]).merging(poses) { _, core in core }
    }
}

public enum PackError: Error, Equatable {
    case missingPoses([String])
    case badContact(String)
}

extension Pack {
    /// Decodes pack.json and checks that `required` poses exist and every anchored pose has a sane contact.
    public static func decode(_ data: Data, required: [String]) throws -> Pack {
        let pack = try JSONDecoder().decode(Pack.self, from: data)
        let missing = required.filter { pack.poses[$0] == nil }.sorted()
        if !missing.isEmpty { throw PackError.missingPoses(missing) }
        for (name, pose) in pack.allPoses.sorted(by: { $0.key < $1.key }) where pose.anchor != .free {
            guard let contact = pose.contact, contact.isValid else { throw PackError.badContact(name) }
        }
        return pack
    }
}
