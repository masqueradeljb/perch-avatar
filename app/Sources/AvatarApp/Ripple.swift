import AppKit

/// An expanding, fading ring where a click landed (CG screen point), in its own click-through panel.
final class Ripple {
    static let size = 64.0
    static let duration = 0.45
    private let panel: NSPanel
    private let ring = CAShapeLayer()

    init() {
        let bounds = NSRect(x: 0, y: 0, width: Self.size, height: Self.size)
        panel = NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: bounds)
        view.wantsLayer = true
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: bounds.insetBy(dx: 3, dy: 3), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = NSColor.systemOrange.cgColor
        ring.lineWidth = 3
        ring.opacity = 0
        view.layer?.addSublayer(ring)
        panel.contentView = view
    }

    func show(x: Double, y: Double) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        panel.setFrameOrigin(NSPoint(x: x - Self.size / 2, y: primaryHeight - y - Self.size / 2))
        panel.orderFrontRegardless()
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.2
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = Self.duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.removeAllAnimations()
        ring.add(group, forKey: "ripple")
    }
}
