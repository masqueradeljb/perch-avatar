import AppKit

enum StatusIcon {
    /// Cat-head silhouette for the status bar: an 18 × 18 pt template image (tinted by the system), eyes cut out.
    static func catHead() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 12)).fill()
            for (a, b, c) in [((2.4, 8.0), (3.4, 16.8), (8.2, 12.8)), ((9.8, 12.8), (14.6, 16.8), (15.6, 8.0))] {
                let ear = NSBezierPath()
                ear.move(to: NSPoint(x: a.0, y: a.1))
                ear.line(to: NSPoint(x: b.0, y: b.1))
                ear.line(to: NSPoint(x: c.0, y: c.1))
                ear.close()
                ear.fill()
            }
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: 4.6, y: 5.6, width: 2.6, height: 3.2)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.8, y: 5.6, width: 2.6, height: 3.2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
