import Foundation

public enum AgentState: String, Codable, CaseIterable {
    case thinking, working, done, error, idle
    case waitingUser = "waiting_user"
}

/// Where a show request wants the character.
/// Wire: {"window": "focused" | "<app name>", "edge": "top|left|right|corner_l|corner_r", "pos": 0–1},
/// {"rect": [x, y, w, h]} or {"text": "...", "window": "<app name>"?} (the text wins when several keys are present).
public enum Target: Equatable {
    /// `app == nil` means the focused window.
    case window(app: String?, edge: String?, pos: Double?)
    /// Screen rect in CG points; a pose with a hotspot points at it.
    case rect(Rect)
    /// Visible text found by OCR in a window (`app == nil` = the current default target window); points at it.
    case text(String, app: String?)
}

extension Target: Codable {
    private enum Key: String, CodingKey { case window, edge, pos, rect, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let text = try c.decodeIfPresent(String.self, forKey: .text) {
            let app = try c.decodeIfPresent(String.self, forKey: .window)
            self = .text(text, app: app == "focused" ? nil : app)
            return
        }
        if let r = try c.decodeIfPresent([Double].self, forKey: .rect) {
            guard r.count == 4 else {
                throw DecodingError.dataCorruptedError(forKey: .rect, in: c, debugDescription: "rect needs [x, y, w, h]")
            }
            self = .rect(Rect(x: r[0], y: r[1], w: r[2], h: r[3]))
            return
        }
        let app = try c.decodeIfPresent(String.self, forKey: .window) ?? "focused"
        self = .window(app: app == "focused" ? nil : app,
                       edge: try c.decodeIfPresent(String.self, forKey: .edge),
                       pos: try c.decodeIfPresent(Double.self, forKey: .pos))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case let .rect(r):
            try c.encode([r.x, r.y, r.w, r.h], forKey: .rect)
        case let .text(text, app):
            try c.encode(text, forKey: .text)
            try c.encodeIfPresent(app, forKey: .window)
        case let .window(app, edge, pos):
            try c.encode(app ?? "focused", forKey: .window)
            try c.encodeIfPresent(edge, forKey: .edge)
            try c.encodeIfPresent(pos, forKey: .pos)
        }
    }
}

public struct ShowRequest: Codable, Equatable {
    public var pose: String?
    public var face: String?
    public var at: Target?
    public var say: String?
    public var fx: String?
    public var holdS: Double?

    enum CodingKeys: String, CodingKey { case pose, face, at, say, fx, holdS = "hold_s" }

    public init(pose: String? = nil, face: String? = nil, at: Target? = nil, say: String? = nil,
                fx: String? = nil, holdS: Double? = nil) {
        self.pose = pose
        self.face = face
        self.at = at
        self.say = say
        self.fx = fx
        self.holdS = holdS
    }
}

public enum Request: Equatable {
    /// `activity` (typing|reading|searching|browsing|running) picks an action pose while busy.
    case state(AgentState, note: String? = nil, activity: String? = nil)
    case show(ShowRequest)
    case targets
}

extension Request: Decodable {
    private enum Key: String, CodingKey { case type, state, note, activity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        switch try c.decode(String.self, forKey: .type) {
        case "state":
            self = .state(try c.decode(AgentState.self, forKey: .state),
                          note: try c.decodeIfPresent(String.self, forKey: .note),
                          activity: try c.decodeIfPresent(String.self, forKey: .activity))
        case "show":
            self = .show(try ShowRequest(from: decoder))
        case "targets":
            self = .targets
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(other)")
        }
    }
}

public struct WindowInfo: Codable, Equatable {
    public var app: String
    public var rect: [Double]
    public var focused: Bool

    public init(app: String, rect: Rect, focused: Bool) {
        self.app = app
        self.rect = [rect.x, rect.y, rect.w, rect.h]
        self.focused = focused
    }
}

public struct Response: Encodable, Equatable {
    public var ok: Bool
    public var error: String?
    public var windows: [WindowInfo]?

    public init(ok: Bool, error: String? = nil, windows: [WindowInfo]? = nil) {
        self.ok = ok
        self.error = error
        self.windows = windows
    }
}

/// A request plus who sent it. `pid` lets the app find the agent's own window (its "home");
/// `window` names the app the agent is working in now ("home" clears it). Both are optional
/// and may ride on any message type.
public struct Envelope: Decodable, Equatable {
    public var request: Request
    public var pid: Int32?
    public var window: String?

    private enum Key: String, CodingKey { case pid, window }

    public init(from decoder: Decoder) throws {
        request = try Request(from: decoder)
        let c = try decoder.container(keyedBy: Key.self)
        pid = try c.decodeIfPresent(Int32.self, forKey: .pid)
        window = try c.decodeIfPresent(String.self, forKey: .window)
    }
}
