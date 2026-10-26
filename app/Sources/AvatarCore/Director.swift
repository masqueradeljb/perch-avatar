/// What the character should be doing now. Placement turns `target` into a position.
public struct Directive: Equatable {
    public var pose: String
    public var face: String?
    public var fx: String?
    public var say: String?
    /// nil = the default target (focused window).
    public var target: Target?

    public init(pose: String, face: String? = nil, fx: String? = nil, say: String? = nil, target: Target? = nil) {
        self.pose = pose
        self.face = face
        self.fx = fx
        self.say = say
        self.target = target
    }
}

public struct DirectorConfig {
    public var defaultHold = 4.0
    /// shock / celebrate / wave length before settling.
    public var reactionTime = 2.0
    public var minDwell = 1.5
    /// error/done moods fade to plain idle after this much quiet.
    public var idleRest = 60.0
    public var idleSleep = 300.0
    /// thinking/working with no news for this long is treated as idle (agent died or forgot).
    public var staleBusy = 120.0

    public init() {}
}

/// Pure behavior: requests in, directive out. Time is passed in so tests can drive it.
public final class Director {
    private let config: DirectorConfig
    private var state: AgentState = .idle
    private var activity: String?
    private var stateAt: Double
    private var lastEventAt: Double
    private var show: (request: ShowRequest, until: Double)?
    private var emitted: Directive?
    private var poseChangedAt = -Double.infinity

    public init(config: DirectorConfig = DirectorConfig(), now: Double) {
        self.config = config
        stateAt = now
        lastEventAt = now
    }

    /// Busy-state action poses by activity; unknown or missing activity uses think/work.
    public static let activityPoses = ["typing": "type", "reading": "read", "searching": "search",
                                       "browsing": "search", "running": "tail_swipe"]

    public func handle(_ request: Request, at now: Double) {
        switch request {
        case let .state(s, _, a):
            state = s
            activity = a
            stateAt = now
            lastEventAt = now
        case let .show(r):
            show = (r, now + (r.holdS ?? config.defaultHold))
            lastEventAt = now
        case .targets:
            break
        }
    }

    public func directive(at now: Double) -> Directive {
        if let s = show, now < s.until {
            let r = s.request
            let d = Directive(pose: r.pose ?? emitted?.pose ?? "lie_edge", face: r.face, fx: r.fx, say: r.say, target: r.at)
            return emit(d, at: now, force: true)
        }
        show = nil
        return emit(stateDirective(at: now), at: now, force: false)
    }

    private func stateDirective(at now: Double) -> Directive {
        let reacting = now - stateAt < config.reactionTime
        let quiet = now - lastEventAt
        switch state {
        case .thinking, .working:
            if quiet < config.staleBusy {
                return Directive(pose: activity.flatMap { Self.activityPoses[$0] } ?? (state == .thinking ? "think" : "work"))
            }
        case .error:
            if reacting { return Directive(pose: "shock", fx: "exclaim") }
            if quiet < config.idleRest { return Directive(pose: "lie_edge", face: "sad") }
        case .done:
            if reacting { return Directive(pose: "celebrate", fx: "sparkle") }
            if quiet < config.idleRest { return Directive(pose: "lie_edge", face: "happy") }
        case .waitingUser:
            if reacting { return Directive(pose: "wave", fx: "question") }
            if quiet < config.idleSleep { return Directive(pose: "sit_corner") }
        case .idle:
            break
        }
        return quiet >= config.idleSleep ? Directive(pose: "sleep", fx: "zzz") : Directive(pose: "lie_edge")
    }

    /// Holds the previous pose (only the pose; face, fx, say and target stay current) until `minDwell` has passed since the last pose change (shows skip this).
    private func emit(_ d: Directive, at now: Double, force: Bool) -> Directive {
        if let e = emitted, e.pose != d.pose, !force, now - poseChangedAt < config.minDwell {
            return Directive(pose: e.pose, face: d.face, fx: d.fx, say: d.say, target: d.target)
        }
        if emitted?.pose != d.pose { poseChangedAt = now }
        emitted = d
        return d
    }
}
