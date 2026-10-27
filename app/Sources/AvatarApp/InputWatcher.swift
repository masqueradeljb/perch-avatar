import AppKit
import AvatarCore

/// Listens (read-only) for clicks, scrolls and key presses that another process posted — computer use.
/// Hardware input carries source pid 0 and is ignored, so the user's own input never moves the mascot.
/// Needs Input Monitoring. Keys are only counted; which key is never read.
final class InputWatcher {
    private let handler: (InputEvent, pid_t) -> Void
    private var tap: CFMachPort?

    init(handler: @escaping (InputEvent, pid_t) -> Void) {
        self.handler = handler
    }

    static var hasPermission: Bool { CGPreflightListenEventAccess() }

    static func requestPermission() {
        _ = CGRequestListenEventAccess()
    }

    /// False when the tap can't be created (no permission).
    func start() -> Bool {
        let types: [CGEventType] = [.leftMouseDown, .scrollWheel, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            if let refcon { Unmanaged<InputWatcher>.fromOpaque(refcon).takeUnretainedValue().receive(type, event) }
            return Unmanaged.passUnretained(event)
        }, userInfo: me) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid != 0, pid != getpid() else { return }
        let p = event.location
        switch type {
        case .leftMouseDown:
            handler(.click(x: p.x, y: p.y), pid)
        case .scrollWheel:
            handler(.scroll(x: p.x, y: p.y, dy: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))), pid)
        case .keyDown:
            handler(.key, pid)
        default:
            break
        }
    }
}
