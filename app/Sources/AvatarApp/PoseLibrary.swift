import AppKit
import AvatarCore

/// Loads a pack and answers: which pose is drawn on which edge for a requested pose,
/// its on-screen box, its image for a face, and its hotspot.
final class PoseLibrary {
    static let required = ["lie_edge", "peek_side", "stand"]

    private struct Entry {
        let pose: Pose
        let image: CGImage
        let faces: [String: CGImage]
        /// Resampled animation frames (empty unless the pose declares 2+).
        let frames: [CGImage]
        let box: PoseBox?
    }

    private var entries: [String: Entry] = [:]
    let packName: String

    init(dir: URL, pointsPerPixel: Double) throws {
        let pack = try Pack.decode(try Data(contentsOf: dir.appendingPathComponent("pack.json")), required: Self.required)
        packName = pack.name
        for (name, pose) in pack.allPoses {
            let source = try Self.load(dir.appendingPathComponent(pose.image))
            let s = pointsPerPixel * (pose.scale ?? 1)
            let box = pose.contact.map { PoseBox(w: Double(source.width) * s, h: Double(source.height) * s, contact: $0) }
            let shrink = s * Self.renderScale
            var faces: [String: CGImage] = [:]
            for (face, path) in pose.faces ?? [:] {
                faces[face] = Self.resample(try Self.load(dir.appendingPathComponent(path)), by: shrink)
            }
            var frames: [CGImage] = []
            if let paths = pose.frames, paths.count >= 2 {
                for path in paths { frames.append(Self.resample(try Self.load(dir.appendingPathComponent(path)), by: shrink)) }
            }
            entries[name] = Entry(pose: pose, image: Self.resample(source, by: shrink), faces: faces, frames: frames, box: box)
        }
    }

    /// Pixels per point the images are pre-scaled to (Retina). 1× displays then only halve them.
    static let renderScale = 2.0

    /// High-quality downscale done once at load. Letting Core Animation shrink a ~800 px image
    /// to ~170 pt every frame (no mipmaps) shows as jagged, shimmering lines in fur and outlines.
    private static func resample(_ image: CGImage, by factor: Double) -> CGImage {
        guard factor < 1 else { return image }
        let w = max(Int((Double(image.width) * factor).rounded()), 1)
        let h = max(Int((Double(image.height) * factor).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    private static func load(_ url: URL) throws -> CGImage {
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "PoseLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot load \(url.path)"])
        }
        return image
    }

    func has(_ name: String) -> Bool { entries[name] != nil }

    /// The pose to draw for `name`: itself if the pack has it with a contact, else a same-anchor fallback.
    /// A missing action pose (type, read, search, tail_swipe) falls back to `work` when the pack has it.
    func resolve(_ name: String) -> String {
        if let e = entries[name], e.box != nil { return name }
        if Director.activityPoses.values.contains(name), let work = entries["work"], work.box != nil { return "work" }
        return entries[name]?.pose.anchor == .edgeTop || name == "sleep" || name == "lie_low" ? "lie_edge" : "stand"
    }

    func anchor(_ name: String) -> AnchorKind { entries[resolve(name)]!.pose.anchor }

    /// Which pose is drawn on each edge when `requested` is wanted.
    func layout(for requested: String) -> [Edge: String] {
        let main = resolve(requested)
        var out: [Edge: String] = [:]
        if anchor(main) != .edgeSide {
            for edge in [Edge.top, .cornerLeft, .cornerRight, .floor, .inset] { out[edge] = main }
        }
        out[.side] = "peek_side"
        return out
    }

    func box(_ name: String) -> PoseBox? { entries[name]?.box }

    func hotspot(_ name: String) -> [Double]? { entries[name]?.pose.hotspot?.tip }

    /// Face image if the pose has it, else the base image.
    func image(_ name: String, face: String?) -> CGImage? {
        guard let e = entries[name] else { return nil }
        return face.flatMap { e.faces[$0] } ?? e.image
    }

    /// Animation frames of a pose (empty when it has fewer than two).
    func frameImages(_ name: String) -> [CGImage] { entries[name]?.frames ?? [] }

    /// Frame rate of a pose's animation (default 4).
    func fps(_ name: String) -> Double { entries[name]?.pose.fps ?? 4 }

    func hasFace(_ name: String, _ face: String) -> Bool { entries[name]?.faces[face] != nil }
}
