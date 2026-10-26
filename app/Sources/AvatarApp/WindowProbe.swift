import AppKit
import AvatarCore

/// Reads window geometry from the window server. All rects are CG space (top-left origin, points).
/// Bounds and owner PID need no Screen Recording permission (window titles would).
enum WindowProbe {
    static let minWidth = 300.0
    static let minHeight = 200.0

    struct Listed {
        let pid: pid_t
        let number: Int
        let app: String
        let rect: Rect
    }

    /// On-screen, visible, layer-0 windows big enough to perch on, front to back.
    static func normalWindows(excludingPID ownPID: pid_t) -> [Listed] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let screens = screenRects()
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  cg.width >= minWidth, cg.height >= minHeight
            else { return nil }
            let rect = Rect(x: cg.minX, y: cg.minY, w: cg.width, h: cg.height)
            guard screens.contains(where: { $0.intersectionArea(rect) > 0 }) else { return nil }
            let number = info[kCGWindowNumber as String] as? Int ?? 0
            return Listed(pid: pid, number: number, app: info[kCGWindowOwnerName as String] as? String ?? "?", rect: rect)
        }
    }

    static func focusedWindow(excludingPID ownPID: pid_t) -> Listed? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownPID else { return nil }
        return normalWindows(excludingPID: ownPID).first { $0.pid == app.processIdentifier }
    }

    /// Frontmost window of the app whose name matches (case-insensitive).
    static func window(ofApp name: String, excludingPID ownPID: pid_t) -> Listed? {
        normalWindows(excludingPID: ownPID).first { $0.app.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Frontmost window owned by `pid`.
    static func window(ofPid pid: Int32, excludingPID ownPID: pid_t) -> Listed? {
        normalWindows(excludingPID: ownPID).first { $0.pid == pid }
    }

    /// Whether `window` is the frontmost normal window on screen (nothing of ours counts).
    static func isFrontmost(_ number: Int, excludingPID ownPID: pid_t) -> Bool {
        normalWindows(excludingPID: ownPID).first?.number == number
    }

    /// Full frames of all displays in CG space.
    static func screenRects() -> [Rect] {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.map { s in
            Rect(x: s.frame.minX, y: primaryHeight - s.frame.maxY, w: s.frame.width, h: s.frame.height)
        }
    }

    /// Full frame and visible frame (minus menu bar and Dock) of the screen holding the rect's center.
    static func screenRects(containing r: Rect) -> (frame: Rect, usable: Rect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let center = NSPoint(x: r.x + r.w / 2, y: primaryHeight - (r.y + r.h / 2))
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.screens[0]
        func cg(_ f: NSRect) -> Rect { Rect(x: f.minX, y: primaryHeight - f.maxY, w: f.width, h: f.height) }
        return (cg(screen.frame), cg(screen.visibleFrame))
    }
}
