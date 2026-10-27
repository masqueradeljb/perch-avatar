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
    /// How long an `act` (a click / scroll / typing burst) is shown.
    public var actHold = 0.8

    public init() {}
}

/// Pure behavior: requests in, directive out. Time is passed in so tests can drive it.
public final class Director {
    private let config: DirectorConfig
    private var state: AgentState = .idle
    private var activity: String?
    private var stateAt: Double
    private var lastEventAt: Double
    private var show: (request: ShowRequest, until: Double, act: Bool)?
    /// A regular show an act cut into; it resumes when the act ends if its time isn't up.
    private var interrupted: (request: ShowRequest, until: Double)?
    /// Pose of the last directive not from an act; a pose-less show keeps it.
    private var restingPose: String?
    /// The last directive came from an act: the busy pose may replace it at once (no minDwell).
    private var lastWasAct = false
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

    /// The short show that plays an act: tap at the point (click/drag), scroll with an arrow, or type there.
    public static func showRequest(for a: ActRequest) -> ShowRequest {
        var at: Target?
        if let x = a.x, let y = a.y { at = .rect(Rect(x: x, y: y, w: 1, h: 1)) }
        switch a.action {
        case .click, .drag: return ShowRequest(pose: "tap", at: at)
        case .scroll: return ShowRequest(pose: "scroll", at: at, fx: a.dir == .up ? "scroll_up" : "scroll_down")
        case .type: return ShowRequest(pose: "type", at: at)
        }
    }

    /// Working or thinking, and heard from recently: posted input now is probably the agent's.
    public func isBusy(at now: Double) -> Bool {
        (state == .working || state == .thinking) && now - lastEventAt < config.staleBusy
    }

    /// An act is on screen now (the character sits where the agent is clicking).
    public func isActing(at now: Double) -> Bool { show.map { $0.act && now < $0.until } ?? false }

    public func handle(_ request: Request, at now: Double) {
        switch request {
        case let .state(s, _, a):
            state = s
            activity = a
            stateAt = now
            lastEventAt = now
        case let .show(r):
            show = (r, now + (r.holdS ?? config.defaultHold), false)
            interrupted = nil
            lastEventAt = now
        case let .act(a):
            if let s = show, !s.act, now < s.until { interrupted = (s.request, s.until) }
            show = (Self.showRequest(for: a), now + config.actHold, true)
            // An act is evidence the agent is alive; isBusy still needs a working/thinking state.
            lastEventAt = now
        case .targets:
            break
        }
    }

    public func directive(at now: Double) -> Directive {
        if let s = show, s.act, now >= s.until {
            if let i = interrupted, now < i.until { show = (i.request, i.until, false) }
            interrupted = nil
        }
        if let s = show, now < s.until {
            let r = s.request
            let d = Directive(pose: r.pose ?? restingPose ?? emitted?.pose ?? "lie_edge",
                              face: r.face, fx: r.fx, say: r.say, target: r.at)
            lastWasAct = s.act
            let out = emit(d, at: now, force: true)
            if !s.act { restingPose = out.pose }
            return out
        }
        show = nil
        let afterAct = lastWasAct
        lastWasAct = false
        let out = emit(stateDirective(at: now), at: now, force: afterAct)
        restingPose = out.pose
        return out
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
