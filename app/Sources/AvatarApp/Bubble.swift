import AppKit
import AvatarCore

/// Click-through speech bubble shown above the character.
final class Bubble {
    static let maxWidth = 260.0
    private let panel: NSPanel
    private let label = NSTextField(wrappingLabelWithString: "")
    private var text: String?

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
        box.layer?.cornerRadius = 12
        box.layer?.borderColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        box.layer?.borderWidth = 2
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .black
        label.maximumNumberOfLines = 4
        box.addSubview(label)
        panel.contentView = box
    }

    /// Shows `text` centered above `character` (CG rect), clamped to its screen and flipped below it when there is no room above; nil hides it.
    func say(_ text: String?, above character: Rect?) {
        guard let text, let c = character else {
            if self.text != nil { panel.orderOut(nil) }
            self.text = nil
            return
        }
        if text != self.text {
            label.stringValue = text
            self.text = text
        }
        let size = label.sizeThatFits(NSSize(width: Bubble.maxWidth - 24, height: 200))
        let w = min(size.width, Bubble.maxWidth - 24) + 24, h = size.height + 16
        label.frame = NSRect(x: 12, y: 8, width: w - 24, height: size.height)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let screen = WindowProbe.screenRects(containing: c).frame
        let x = min(max(c.x + c.w / 2 - w / 2, screen.x), max(screen.maxX - w, screen.x))
        var topCG = c.y - h - 6
        if topCG < screen.y { topCG = c.maxY + 6 }  // no room above: go below the character
        topCG = min(max(topCG, screen.y), max(screen.maxY - h, screen.y))
        panel.setFrame(NSRect(x: x, y: primaryHeight - topCG - h, width: w, height: h), display: true)
        applyOrder()
    }

    /// Window number to sit directly above; nil = front of everything.
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
            panel.level = .statusBar
            panel.orderFrontRegardless()
        }
    }
}
