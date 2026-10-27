import AppKit
import AvatarCore

/// Transparent, click-through panel drawing the character (plus fx stickers in a margin around it).
final class Stage {
    /// Room around the character for stickers; the panel is click-through, so the margin is harmless.
    static let margin = 56.0

    private let panel: NSPanel
    /// Carries the horizontal mirror; `imageLayer` inside it only animates (breathing, squash, fade).
    private let flipLayer = CALayer()
    private let imageLayer = CALayer()
    private let fxLayer = CATextLayer()
    private var current: (name: String, mirrored: Bool)?
    private var fx: String?
    private(set) var characterFrame: Rect?

    private var currentImage: CGImage?
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    /// Window number to sit directly above; nil = front of everything (above the menu bar).
    private var orderAbove: Int?

    func setOrder(above number: Int?) {
        orderAbove = number
        if panel.isVisible { applyOrder() }
    }

    private func applyOrder() {
        if let n = orderAbove {
            panel.level = .normal
            panel.order(.above, relativeTo: n)
        } else {
            panel.level = .statusBar  // above the menu bar: perched poses may rise into it
            panel.orderFrontRegardless()
        }
    }

    /// True when the global CG point is over an opaque pixel of the character.
    func hitTest(_ p: (x: Double, y: Double)) -> Bool {
        guard let f = characterFrame, let image = currentImage,
              p.x >= f.x, p.x < f.maxX, p.y >= f.y, p.y < f.maxY else { return false }
        var u = (p.x - f.x) / f.w
        if current?.mirrored == true { u = 1 - u }
        let px = min(Int(u * Double(image.width)), image.width - 1)
        let py = min(Int((p.y - f.y) / f.h * Double(image.height)), image.height - 1)
        var alpha: UInt8 = 0
        guard let ctx = CGContext(data: &alpha, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: -px, y: -(image.height - 1 - py), width: image.width, height: image.height))
        return alpha > 40
    }

    /// Click-through except while the cursor is over the character.
    func setInteractive(_ on: Bool) {
        if panel.ignoresMouseEvents == on { panel.ignoresMouseEvents = !on }
    }

    static let fxGlyph = ["exclaim": "❗", "question": "❓", "sparkle": "✨", "zzz": "💤",
                          "sweat": "💦", "speedlines": "💨", "scroll_up": "⏫", "scroll_down": "⏬"]

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar  // above the menu bar: perched poses may rise into it
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = CharacterView()
        view.onDoubleClick = { [weak self] in self?.onDoubleClick?() }
        view.onRightClick = { [weak self] event in self?.onRightClick?(event) }
        view.wantsLayer = true
        flipLayer.addSublayer(imageLayer)
        view.layer?.addSublayer(flipLayer)
        view.layer?.addSublayer(fxLayer)
        panel.contentView = view
        imageLayer.contentsGravity = .resize
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0)  // breathe from the bottom
        fxLayer.fontSize = 30
        fxLayer.alignmentMode = .center
        fxLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    /// Draws `image` at `placement`. A new pose name (or facing) plays a short squash-and-fade;
    /// a face change on the same pose swaps instantly.
    func show(name: String, image: CGImage, placement: Placement) {
        let f = placement.frame
        characterFrame = f
        setPanelFrame(around: f)
        setPose(name: name, image: image, w: f.w, h: f.h, mirrored: placement.mirrored)
        applyOrder()
    }

    /// Moves to a far spot on the same window without teleporting: the new pose appears where
    /// the character stands (bottom-centers aligned) and slides to `placement` in 0.3 s.
    func glide(name: String, image: CGImage, placement: Placement, completion: @escaping () -> Void) {
        let f = placement.frame
        guard let from = characterFrame else {
            show(name: name, image: image, placement: placement)
            return completion()
        }
        let start = Rect(x: from.x + from.w / 2 - f.w / 2, y: from.maxY - f.h, w: f.w, h: f.h)
        characterFrame = start
        setPanelFrame(around: start)
        setPose(name: name, image: image, w: f.w, h: f.h, mirrored: placement.mirrored)
        applyOrder()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(Stage.appKitRect(around: f), display: true)
        }, completionHandler: { [weak self] in
            self?.characterFrame = f
            completion()
        })
    }

    /// Swaps the drawn pose (squash-and-fade when the pose or facing changes).
    private func setPose(name: String, image: CGImage, w: Double, h: Double, mirrored: Bool) {
        let poseChanged = current.map { $0.name != name || $0.mirrored != mirrored } ?? true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentImage = image
        imageLayer.contents = image
        layoutCharacter(w: w, h: h, mirrored: mirrored)
        current = (name, mirrored)  // before layoutFx: the fx side follows the new facing
        layoutFx()
        CATransaction.commit()
        if poseChanged { playSwap() }
    }

    func setBreathing(_ on: Bool) {
        if on, imageLayer.animation(forKey: "breathe") == nil {
            let a = CABasicAnimation(keyPath: "transform.scale.y")
            a.fromValue = 1.0
            a.toValue = 1.018
            a.duration = 1.7
            a.autoreverses = true
            a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            imageLayer.add(a, forKey: "breathe")
        } else if !on {
            imageLayer.removeAnimation(forKey: "breathe")
        }
    }

    func setFx(_ name: String?) {
        guard name != fx else { return }
        fx = name
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fxLayer.string = name.flatMap { Stage.fxGlyph[$0] }
        layoutFx()
        CATransaction.commit()
        if name != nil {
            let pop = CABasicAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.3
            pop.toValue = 1
            pop.duration = 0.18
            fxLayer.add(pop, forKey: "pop")
        }
    }

    /// Runs the character (with `image`, e.g. the run pose) from its current frame to `to`.
    func travel(image: CGImage, to: Rect, mirrored: Bool, completion: @escaping () -> Void) {
        guard let from = characterFrame else { return completion() }
        setBreathing(false)
        let distance = hypot(to.x - from.x, to.y - from.y)
        let duration = min(max(distance / 1600, 0.2), 0.6)
        let runFrame = Rect(x: from.x, y: from.y + from.h - to.h, w: to.w, h: to.h)
        setPanelFrame(around: runFrame)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        currentImage = image
        imageLayer.contents = image
        layoutCharacter(w: to.w, h: to.h, mirrored: mirrored)
        CATransaction.commit()
        current = ("run", mirrored)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(Stage.appKitRect(around: to), display: true)
        }, completionHandler: { [weak self] in
            // Arrived: without this the next tick still measures from the start point and runs again.
            self?.characterFrame = to
            completion()
        })
    }

    func hide() {
        panel.orderOut(nil)
        current = nil
        characterFrame = nil
    }

    private func playSwap() {
        let squash = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squash.values = [0.88, 1.04, 1.0]
        squash.keyTimes = [0, 0.6, 1]
        squash.duration = 0.22
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.2
        fade.toValue = 1
        fade.duration = 0.15
        imageLayer.add(squash, forKey: "squash")
        imageLayer.add(fade, forKey: "fade")
    }

    /// Sizes the flip container to the character frame (mirror about its center) and the image inside it.
    private func layoutCharacter(w: Double, h: Double, mirrored: Bool) {
        flipLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        flipLayer.position = CGPoint(x: Stage.margin + w / 2, y: Stage.margin + h / 2)
        flipLayer.transform = CATransform3DMakeScale(mirrored ? -1 : 1, 1, 1)
        imageLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        imageLayer.position = CGPoint(x: w / 2, y: 0)  // anchor is bottom-center
    }

    private func layoutFx() {
        guard let f = characterFrame else { return }
        let mirrored = current?.mirrored ?? false
        let x = Stage.margin + (mirrored ? f.w * 0.1 : f.w * 0.9)
        fxLayer.bounds = CGRect(x: 0, y: 0, width: 44, height: 40)
        fxLayer.position = CGPoint(x: x, y: Stage.margin + f.h + 10)
    }

    private func setPanelFrame(around f: Rect) {
        panel.setFrame(Stage.appKitRect(around: f), display: true)
    }

    /// Character frame (CG) → panel frame (AppKit, bottom-left origin) including the margin.
    static func appKitRect(around f: Rect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let m = margin
        return NSRect(x: f.x - m, y: primaryHeight - f.y - f.h - m, width: f.w + 2 * m, height: f.h + 2 * m)
    }
}

/// Content view that reports double- and right-clicks on the character.
final class CharacterView: NSView {
    var onDoubleClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}
