import AppKit
import AvatarCore
import ServiceManagement

/// Runs the Director against socket requests and renders its directive on the target window at 60 Hz.
final class AppController: NSObject, NSApplicationDelegate {
    private let packDir: URL
    private let pointsPerPixel: Double
    private var library: PoseLibrary!
    private var stage: Stage!
    private var bubble: Bubble!
    private var director: Director!
    private var server: SocketServer?
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var forced: Edge?
    private var lastTarget: Rect?
    private var traveling = false
    /// Target window seen on the previous tick; a pose change on the same window never runs.
    private var lastWindow: (pid: pid_t, rect: Rect)?
    private var lastRunAt = -Double.infinity
    static let runCooldown = 3.0
    /// Same-window moves longer than this glide instead of jumping.
    static let glideDistance = 120.0
    /// OCR results per "windowNumber|query"; a nil rect means the text was not found.
    private var textHits: [String: (rect: Rect?, at: Double)] = [:]
    private var textInFlight: Set<String> = []
    static let textRefresh = 3.0
    /// Windows of the named app searched for text, front to back.
    static let textWindowLimit = 5
    private var blinkUntil = 0.0
    private var nextBlink = 0.0
    private var ripple: Ripple!
    private var watcher: InputWatcher?
    private let coalescer = ActCoalescer()
    private var ignoreApps: Set<String> = []
    private var actionsItem: NSMenuItem!

    enum FollowMode: String { case focus, agent }
    private var mode: FollowMode = .focus
    private var homePid: Int32?
    private var workApp: String?
    private var modeItems: [NSMenuItem] = []
    /// Window the panels were last ordered above (`.some(nil)` = front); avoids reordering every tick.
    private var lastAbove: Int??

    static let cornerOrder: [Edge] = [.cornerRight, .cornerLeft, .top, .side, .floor]
    static let edgeNames: [String: [Edge]] = ["top": [.top], "left": [.side], "right": [.side],
                                              "corner_l": [.cornerLeft], "corner_r": [.cornerRight]]

    init(packDir: URL, pointsPerPixel: Double) {
        self.packDir = packDir
        self.pointsPerPixel = pointsPerPixel
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            library = try PoseLibrary(dir: packDir, pointsPerPixel: pointsPerPixel)
        } catch {
            fputs("Perch: \(error)\n", stderr)
            exit(1)
        }
        stage = Stage()
        stage.onDoubleClick = { [weak self] in self?.toggleMode() }
        stage.onRightClick = { [weak self] event in self?.showContextMenu(event) }
        bubble = Bubble()
        ripple = Ripple()
        director = Director(now: now)
        let server = SocketServer { [weak self] envelope in self?.handle(envelope) ?? Response(ok: false) }
        do {
            try server.start()
            self.server = server
        } catch {
            fputs("Perch: socket disabled: \(error)\n", stderr)
        }
        setUpMenu()
        ignoreApps = PerchConfig.ignoreApps(home: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".perch"))
        startWatcher()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func handle(_ envelope: Envelope) -> Response {
        if let pid = envelope.pid {
            homePid = resolveHome(pid: pid, parent: ProcessTree.parent(of:)) {
                WindowProbe.window(ofPid: $0, excludingPID: getpid()) != nil
            } ?? homePid
        }
        if let w = envelope.window { workApp = (w == "home") ? nil : w }
        let request = envelope.request
        if case .targets = request {
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let windows = WindowProbe.normalWindows(excludingPID: getpid()).map {
                WindowInfo(app: $0.app, rect: $0.rect, focused: $0.pid == front)
            }
            return Response(ok: true, windows: windows)
        }
        if case let .act(a) = request {
            perform(a)
            return Response(ok: true)
        }
        director.handle(request, at: now)
        return Response(ok: true)
    }

    private func tick() {
        let m = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        stage.setInteractive(stage.hitTest((x: Double(m.x), y: Double(primaryHeight - m.y))))
        guard !traveling else { return }
        let t = now
        let d = resolveText(director.directive(at: t), at: t)
        guard let (name, placement, window) = place(d) else {
            stage.hide()
            bubble.say(nil, above: nil)
            statusItem.button?.title = "🐾"
            lastTarget = nil
            lastWindow = nil
            lastAbove = nil
            return
        }
        let changed = window.map { w in lastWindow.map { windowChanged(from: $0, to: (w.pid, w.rect)) } ?? false } ?? false
        if let window { lastWindow = (window.pid, window.rect) }
        let frames = d.face == nil ? library.frameImages(name) : []
        let face = frames.isEmpty ? blinkFace(for: name, face: d.face, at: t) : nil
        guard let image = frames.isEmpty ? library.image(name, face: face)
                                         : frames[Int(t * library.fps(name)) % frames.count] else { return }

        if let from = stage.characterFrame, changed, t - lastRunAt >= Self.runCooldown,
           library.has("run"), let run = library.image("run", face: nil), let runBox = runBox(height: placement.frame.h) {
            traveling = true
            lastRunAt = t
            let target = Rect(x: placement.frame.x, y: placement.frame.maxY - runBox.h, w: runBox.w, h: runBox.h)
            stage.setFx("speedlines")
            bubble.say(nil, above: nil)
            stage.travel(image: run, to: target, mirrored: placement.frame.x < from.x) { [weak self] in
                self?.traveling = false
            }
            lastTarget = placement.frame
            return
        }
        if let from = stage.characterFrame,
           hypot(placement.frame.x - from.x, placement.frame.maxY - from.maxY) > Self.glideDistance {
            // Same window but far away (pointing, a corner): slide there; the bubble waits for arrival.
            traveling = true
            bubble.say(nil, above: nil)
            stage.glide(name: name, image: image, placement: placement) { [weak self] in
                self?.traveling = false
            }
            updateOrder(for: window?.number)
            lastTarget = placement.frame
            return
        }
        stage.show(name: name, image: image, placement: placement)
        updateOrder(for: window?.number)
        stage.setBreathing(true)
        stage.setFx(d.fx)
        bubble.say(d.say, above: placement.frame)
        statusItem.button?.title = "🐾 \(mode == .agent ? "agent" : "focus") · \(name)"
        lastTarget = placement.frame
    }

    /// Chooses the drawn pose and its placement for a directive.
    /// Also returns the target window (nil when pointing at a rect) for run decisions.
    private func place(_ d: Directive) -> (String, Placement, (pid: pid_t, rect: Rect, number: Int)?)? {
        if case let .rect(r)? = d.target {
            let head = library.resolve(d.pose)
            let usable = WindowProbe.screenRects(containing: r).usable
            if let picked = Placer.pickPointing(r, candidates: library.pointCandidates(head), usable: usable,
                                                near: stage.characterFrame) {
                return (picked.name, picked.placement, nil)
            }
            // A pose that can't point (scroll, type) perches on top of the window under the point, above it.
            if let w = WindowProbe.window(at: r, excludingPID: getpid()) {
                var perch = d
                perch.target = .window(app: w.app, edge: "top", pos: (r.x - w.rect.x) / w.rect.w)
                return place(perch)
            }
        }
        var window: WindowProbe.Listed?
        var preferRight: Bool?
        var order = forced.map { [$0] } ?? (library.anchor(d.pose) == .corner ? Self.cornerOrder : Placer.defaultOrder)
        var pos = 0.7
        if case let .window(app, edge, p)? = d.target {
            window = app.flatMap { WindowProbe.window(ofApp: $0, excludingPID: getpid()) }
            if let edge, let o = Self.edgeNames[edge] { order = o + Placer.defaultOrder }
            if edge == "left" { preferRight = false } else if edge == "right" { preferRight = true }
            if let p { pos = p }
        }
        let defaultWindow = defaultTargetWindow()
        guard let listed = window ?? defaultWindow else { return nil }
        let w = listed.rect
        let layout = library.layout(for: d.pose)
        var boxes: [Edge: PoseBox] = [:]
        for (edge, name) in layout { boxes[edge] = library.box(name) }
        let display = WindowProbe.screenRects(containing: w)
        let input = PlacementInput(window: w, usable: display.usable, screen: display.frame,
                                   boxes: boxes, order: order, topPos: pos, preferRight: preferRight)
        guard let p = Placer.resolve(input), let name = layout[p.edge] else { return nil }
        return (name, p, (listed.pid, w, listed.number))
    }

    /// The window the character follows when a directive names none (depends on the follow mode).
    private func defaultTargetWindow() -> WindowProbe.Listed? {
        guard mode == .agent else { return WindowProbe.focusedWindow(excludingPID: getpid()) }
        if let app = workApp, let w = WindowProbe.window(ofApp: app, excludingPID: getpid()) { return w }
        if let pid = homePid, let w = WindowProbe.window(ofPid: pid, excludingPID: getpid()) { return w }
        return WindowProbe.focusedWindow(excludingPID: getpid())
    }

    /// Turns a `.text` target into something placeable: the OCR'd rect once known (refreshed every few
    /// seconds in the background), otherwise a perch on the window; a failed lookup adds the `question` fx.
    private func resolveText(_ d: Directive, at t: Double) -> Directive {
        guard case let .text(query, app)? = d.target else {
            if !textHits.isEmpty { textHits = textHits.filter { $0.value.rect != nil } }
            return d
        }
        var out = d
        out.target = .window(app: app, edge: nil, pos: nil)
        // An app usually has several windows (and dialogs in front); search them front to back.
        let candidates: [WindowProbe.Listed] = app.map { name in
            WindowProbe.normalWindows(excludingPID: getpid()).filter { $0.app.caseInsensitiveCompare(name) == .orderedSame }
        } ?? (defaultTargetWindow().map { [$0] } ?? [])
        guard !candidates.isEmpty else { return out }
        let key = "\(app ?? "default")|\(query)"
        let hit = textHits[key]
        if hit == nil || (hit!.rect != nil && t - hit!.at >= Self.textRefresh), !textInFlight.contains(key) {
            textInFlight.insert(key)
            let windows = candidates.prefix(Self.textWindowLimit).map { (number: $0.number, frame: $0.rect) }
            Task { [weak self] in
                var r: Rect?
                for w in windows where r == nil {
                    r = await TextLocator.find(query, windowNumber: w.number, frame: w.frame)
                }
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.textInFlight.remove(key)
                    self.textHits[key] = (r, self.now)
                }
            }
        }
        if let hit {
            if let r = hit.rect { out.target = .rect(r) } else { out.fx = "question" }
        }
        return out
    }

    /// Sits the panels directly above the target window, or in front of everything when it is frontmost.
    private func updateOrder(for number: Int?) {
        let above: Int? = number.flatMap { WindowProbe.isFrontmost($0, excludingPID: getpid()) ? nil : $0 }
        if let last = lastAbove, last == above { return }
        lastAbove = .some(above)
        stage.setOrder(above: above)
        bubble.setOrder(above: above)
    }

    private func runBox(height: Double) -> PoseBox? {
        guard let img = library.image("run", face: nil) else { return nil }
        let s = height / Double(img.height)
        return PoseBox(w: Double(img.width) * s, h: height, contact: Contact(x: [0, 1], y: [1, 1]))
    }

    /// A different app's window, or the same one that jumped a long way in one tick (a drag moves gradually).
    private func windowChanged(from: (pid: pid_t, rect: Rect), to: (pid: pid_t, rect: Rect)) -> Bool {
        from.pid != to.pid || hypot(to.rect.x - from.rect.x, to.rect.y - from.rect.y) > 250
    }

    /// Blinks every 3–6 s for 0.12 s when the pose has a blink face and no face is requested.
    private func blinkFace(for name: String, face: String?, at t: Double) -> String? {
        guard face == nil, library.hasFace(name, "blink") else { return face }
        if t >= nextBlink {
            blinkUntil = t + 0.12
            nextBlink = t + Double.random(in: 3...6)
        }
        return t < blinkUntil ? "blink" : nil
    }

    /// Watches posted input when Input Monitoring is granted; the menu item says which.
    private func startWatcher() {
        if watcher == nil, InputWatcher.hasPermission {
            let w = InputWatcher { [weak self] event, pid in self?.received(event, from: pid) }
            if w.start() { watcher = w }
        }
        actionsItem.title = watcher != nil ? "Desktop actions: on" : "Desktop actions: grant Input Monitoring, then relaunch…"
        actionsItem.action = watcher != nil ? nil : #selector(requestInputMonitoring)
    }

    /// Posted input counts as the agent's only while it is busy, and never from an ignored app.
    private func received(_ event: InputEvent, from pid: pid_t) {
        let t = now
        guard director.isBusy(at: t) else { return }
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName?.lowercased(),
           ignoreApps.contains(name) { return }
        if let act = coalescer.feed(event, at: t) { perform(act) }
    }

    private func perform(_ act: ActRequest) {
        if act.action == .click || act.action == .drag, let x = act.x, let y = act.y { ripple.show(x: x, y: y) }
        director.handle(.act(act), at: now)
    }

    @objc private func requestInputMonitoring() {
        InputWatcher.requestPermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func simulateAct(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ActAction(rawValue: raw),
              let w = WindowProbe.focusedWindow(excludingPID: getpid()) else { return }
        perform(ActRequest(action: action, x: w.rect.x + w.rect.w / 2, y: w.rect.y + w.rect.h / 2,
                           dir: action == .scroll ? .down : nil, source: "menu"))
    }

    private func setUpMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐾"
        statusItem.button?.toolTip = "Perch"
        let menu = NSMenu()
        modeItems = Self.modes.map { title, m in
            let item = NSMenuItem(title: title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.representedObject = m.rawValue
            item.target = self
            menu.addItem(item)
            return item
        }
        rebuildModeItems()
        menu.addItem(.separator())
        let simulate = NSMenu()
        for state in AgentState.allCases {
            let item = NSMenuItem(title: state.rawValue, action: #selector(simulate(_:)), keyEquivalent: "")
            item.representedObject = state.rawValue
            item.target = self
            simulate.addItem(item)
        }
        let say = NSMenuItem(title: "say hello", action: #selector(simulateSay), keyEquivalent: "")
        say.target = self
        simulate.addItem(say)
        for (title, action) in [("click (focused window)", ActAction.click), ("scroll down (focused window)", .scroll)] {
            let item = NSMenuItem(title: title, action: #selector(simulateAct(_:)), keyEquivalent: "")
            item.representedObject = action.rawValue
            item.target = self
            simulate.addItem(item)
        }
        let simulateItem = NSMenuItem(title: "Simulate", action: nil, keyEquivalent: "")
        simulateItem.submenu = simulate
        menu.addItem(simulateItem)
        actionsItem = NSMenuItem(title: "Desktop actions", action: nil, keyEquivalent: "")
        actionsItem.target = self
        menu.addItem(actionsItem)
        menu.addItem(.separator())
        let auto = NSMenuItem(title: "Auto", action: #selector(pickEdge(_:)), keyEquivalent: "")
        auto.tag = -1
        auto.target = self
        auto.state = .on
        menu.addItem(auto)
        for (index, edge) in Edge.allCases.enumerated() where edge != .pointing {
            let item = NSMenuItem(title: "Force \(edge.rawValue)", action: #selector(pickEdge(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            fputs("Perch: launch at login unavailable (needs the installed app bundle): \(error)\n", stderr)
        }
        sender.state = service.status == .enabled ? .on : .off
    }

    static let modes: [(String, FollowMode)] = [("Follow focused window", .focus), ("Follow agent window", .agent)]

    private func toggleMode() {
        setMode(mode == .focus ? .agent : .focus)
    }

    private func setMode(_ m: FollowMode) {
        mode = m
        let say = m == .agent ? "Back to the agent's window" : "Following you"
        director.handle(.show(ShowRequest(pose: "wave", say: say, holdS: 1.5)), at: now)
        rebuildModeItems()
    }

    private func rebuildModeItems() {
        for item in modeItems { item.state = (item.representedObject as? String) == mode.rawValue ? .on : .off }
    }

    private func showContextMenu(_ event: NSEvent) {
        let menu = NSMenu()
        for (title, m) in Self.modes {
            let item = NSMenuItem(title: title, action: #selector(pickMode(_:)), keyEquivalent: "")
            item.representedObject = m.rawValue
            item.state = mode == m ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: event.window?.contentView ?? NSView())
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let m = FollowMode(rawValue: raw) { setMode(m) }
    }

    @objc private func simulate(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let state = AgentState(rawValue: raw) else { return }
        director.handle(.state(state, note: nil), at: now)
    }

    @objc private func simulateSay() {
        director.handle(.show(ShowRequest(pose: "wave", say: "Hi! I'm \(library.packName).", holdS: 3)), at: now)
    }

    @objc private func pickEdge(_ sender: NSMenuItem) {
        forced = sender.tag < 0 ? nil : Edge.allCases[sender.tag]
        for item in sender.menu?.items ?? [] where item.action == #selector(pickEdge(_:)) {
            item.state = item === sender ? .on : .off
        }
    }
}
