import AppKit
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, UNUserNotificationCenterDelegate {
    private let defaults = UserDefaults.standard
    private var soloEngine = Pomodoro()
    let party = PartyClient()
    var soloSettings: PomodoroSettings { soloEngine.settings }
    var engine: Pomodoro {
        get { party.state?.timer ?? soloEngine }
        set { soloEngine = newValue }
    }
    var timerNow: Date { party.joined ? party.now : Date() }
    private var partyWindow: PartyWindow?
    private var desktop: DesktopTimer?
    private var cachedProfile: ChimpProfile?

    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var timerView: TimerViewController!
    private var settingsWindow: SettingsController?
    private var refreshTimer: Timer?
    private var completionPanel: CompletionPanel?
    private var observers: [NSObjectProtocol] = []
    private let notificationCenter = UNUserNotificationCenter.current()
    private let notificationID = "chimpodoro.session"
    var chimpImages = [ChimpMark.image(size: 42), ChimpMark.image(size: 42, resting: true)]
    private let statusImages = [ChimpMark.image(size: 20), ChimpMark.image(size: 20, resting: true)]
    var soundEnabled: Bool { defaults.object(forKey: "soundEnabled") as? Bool ?? true }
    var notificationsEnabled: Bool { defaults.bool(forKey: "notificationsEnabled") }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var taskName: String {
        get { defaults.string(forKey: "taskName") ?? "" }
        set { defaults.set(newValue, forKey: "taskName") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let identifier = Bundle.main.bundleIdentifier ?? "local.ben.chimpodoro"
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: []); NSApp.terminate(nil); return
        }
        if let data = defaults.data(forKey: "timerState") {
            do { engine = try JSONDecoder().decode(Pomodoro.self, from: data) }
            catch { defaults.set(data, forKey: "unreadableTimerState") }
        }
        notificationCenter.delegate = self
        configureMainMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = status.button {
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            button.target = self; button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        timerView = TimerViewController(); timerView.owner = self
        popover.contentViewController = timerView
        popover.contentSize = NSSize(width: 344, height: 532)
        popover.behavior = .transient; popover.animates = false; popover.delegate = self
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observers.append(workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.pulse() })
        observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.pulse()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in self?.pulse() })
        party.onJoined = { [weak self] in
            guard let self else { return }
            self.soloEngine.pause(at: Date()); self.persist(); self.completionPanel?.close()
        }
        party.onLeft = { [weak self] in self?.completionPanel?.close(); self?.pulse() }
        party.onChange = { [weak self] in
            guard let self else { return }
            if self.cachedProfile != self.party.profile {
                self.cachedProfile = self.party.profile
                self.chimpImages = [ChimpAvatar.image(self.party.profile, size:42), ChimpAvatar.image(self.party.profile,size:42,resting:true)]
            }
            self.partyWindow?.refresh(); self.pulse()
        }
        party.onCompletion = { [weak self] completion in
            guard let self else { return }
            self.finish(PomodoroCompletion(phase:completion.phase,completedAt:Date(timeIntervalSince1970:completion.at),nextPhase:self.engine.phase),at:self.party.now)
        }
        party.onChange?()
        party.restore()
        pulse()
        if defaults.bool(forKey:"desktopOpen") { showDesktop() } else { showTimer() }
    }

    private func configureMainMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let preferences = appMenu.addItem(withTitle: "Chimpodoro Settings…", action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self
        let desktopItem = appMenu.addItem(withTitle:"Open desktop timer",action:#selector(showDesktop),keyEquivalent:"d");desktopItem.target=self
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: "Quit Chimpodoro", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        let editItem = NSMenuItem(); bar.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(selector), keyEquivalent: key)
        }
        let timerItem = NSMenuItem(); bar.addItem(timerItem)
        let timerMenu = NSMenu(title: "Timer"); timerItem.submenu = timerMenu
        let reset = timerMenu.addItem(withTitle: "Reset timer", action: #selector(resetTimer), keyEquivalent: "r"); reset.target = self
        let skip = timerMenu.addItem(withTitle: "Skip session", action: #selector(skipTimer), keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!)); skip.target = self
        NSApp.mainMenu = bar
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDesktop(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        // The saved absolute deadline is restored on the next launch.
        refreshTimer?.invalidate()
        timerView?.view.window?.makeFirstResponder(nil)
        desktop?.timerView.view.window?.makeFirstResponder(nil)
        party.shutdown()
    }
    func popoverDidShow(_ notification: Notification) {
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
        pulse()
    }
    func popoverDidClose(_ notification: Notification) { pulse() }

    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu(); return }
        if popover.isShown { popover.performClose(nil) } else { showTimer() }
    }
    @objc func showTimer() {
        guard let button = status?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "") {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        add("Open Chimpodoro", #selector(showTimer))
        add("Open desktop timer", #selector(showDesktop), "d")
        add("Party & your chimp…", #selector(showParty))
        menu.addItem(.separator())
        add(engine.isRunning ? "Pause" : engine.isPaused ? "Resume" : "Start \(engine.phase.title)", #selector(toggleTimer))
        add("Reset timer", #selector(resetTimer), "r")
        add("Skip session", #selector(skipTimer))
        menu.addItem(.separator())
        add("Settings…", #selector(showSettings), ",")
        add("Quit Chimpodoro", #selector(quit), "q")
        status.menu = menu; status.button?.performClick(nil); status.menu = nil
    }

    private func finish(_ completion: PomodoroCompletion?, at now: Date) {
        guard let completion else { return }
        persist()
        notifyCompletion(completion)
        completionPanel?.close()
        let panel = CompletionPanel(phase: completion.phase, next: engine.phase, running: engine.isRunning, waitingForHost: party.joined && !party.isHost)
        panel.onNext = { [weak self, weak panel] in
            panel?.close()
            guard let self else { return }
            // Reconcile first: an autostarted session may already have elapsed.
            self.pulse()
            if self.party.joined && !self.party.isHost { self.showParty(); return }
            if !self.engine.isRunning { self.toggleTimer() }
            self.showTimer()
        }
        completionPanel = panel
        panel.show()
        if soundEnabled && now.timeIntervalSince(completion.completedAt) < 90 {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(soloEngine) { defaults.set(data, forKey: "timerState") }
    }
    private func pulse() {
        let now = timerNow
        if !party.joined { finish(engine.tick(at: now), at: now) }
        render(at: now)
        scheduleRefresh(at: now)
    }
    private func render(at now: Date) {
        let remaining = engine.remaining(at: now)
        status.button?.image = statusImages[engine.phase == .focus ? 0 : 1]
        if engine.isRunning { status.button?.title = " \(Int(ceil(remaining / 60)))m" }
        else if engine.isPaused { status.button?.title = " Ⅱ" }
        else { status.button?.title = "" }
        let state = engine.isRunning ? "running" : engine.isPaused ? "paused" : "ready"
        status.button?.toolTip = "Chimpodoro · \(engine.phase.title) · \(state) · \(Int(ceil(remaining / 60))) min"
        status.button?.setAccessibilityLabel("Chimpodoro, \(engine.phase.title), \(state), \(Int(ceil(remaining / 60))) minutes remaining")
        if popover.isShown { timerView.render(engine, at: now) }
        if desktop?.visible == true { desktop?.timerView.render(engine,at:now) }
    }
    private func scheduleRefresh(at now: Date) {
        refreshTimer?.invalidate(); refreshTimer = nil
        guard engine.isRunning else { return }
        if party.joined && engine.remaining(at: now) <= 0 { return }
        let remaining = engine.remaining(at: now)
        let remainder = remaining.truncatingRemainder(dividingBy: 60)
        let boundary = remainder > 0.02 ? remainder : 60
        let visible = popover.isShown || desktop?.visible == true
        let delay = visible ? min(1, remaining) : min(boundary, remaining)
        let timer = Timer(timeInterval: max(0.02, delay + 0.01), repeats: false) { [weak self] _ in self?.pulse() }
        timer.tolerance = visible ? 0.1 : min(0.5, remaining / 100)
        RunLoop.main.add(timer, forMode: .common); refreshTimer = timer
    }

    @objc func toggleTimer() {
        if party.joined { completionPanel?.close(); party.action(engine.isRunning ? "pause" : "start"); return }
        let now = Date()
        let completion = engine.isRunning ? engine.pause(at: now) : engine.start(at: now)
        finish(completion, at: now); persist(); pulse()
    }
    @objc func resetTimer() {
        if party.joined { completionPanel?.close(); party.action("reset"); return }
        completionPanel?.close()
        let now = Date(); finish(engine.reset(at: now), at: now); persist(); pulse()
    }
    @objc func skipTimer() {
        if party.joined { completionPanel?.close(); party.action("skip"); return }
        completionPanel?.close()
        let now = Date(); finish(engine.skip(at: now), at: now); persist(); pulse()
    }
    func selectPhase(_ phase: PomodoroPhase) {
        if party.joined { if phase != engine.phase { party.action("select", phase:phase) }; return }
        guard phase != engine.phase else { return }
        completionPanel?.close()
        let now = Date(); finish(engine.select(phase, at: now), at: now); persist(); pulse()
    }
    @objc func showDesktop() {
        popover.performClose(nil)
        if desktop == nil { desktop = DesktopTimer(app:self); desktop?.onVisibilityChange = { [weak self] in self?.pulse() } }
        defaults.set(true,forKey:"desktopOpen")
        desktop?.present();pulse()
    }
    func showChimpCustomization() {
        showParty()
        partyWindow?.focusCustomization()
    }
    @objc func showParty() {
        popover.performClose(nil)
        if partyWindow == nil { partyWindow = PartyWindow(app:self) }
        partyWindow?.refresh(); NSApp.activate(ignoringOtherApps:true)
        partyWindow?.showWindow(nil); partyWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil { settingsWindow = SettingsController(owner: self) }
        settingsWindow?.refresh()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.showWindow(nil); settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }

    func applySettings(_ settings: PomodoroSettings, sound: Bool, notifications: Bool, login: Bool) {
        let now = Date()
        if !party.joined { finish(engine.updateSettings(settings, at: now), at: now) }
        defaults.set(sound, forKey: "soundEnabled")
        if notifications != notificationsEnabled { setNotifications(notifications) }
        if login != launchAtLogin {
            do {
                if login { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                if SMAppService.mainApp.status == .requiresApproval {
                    let alert = NSAlert(); alert.messageText = "Allow Chimpodoro at login"
                    alert.informativeText = "macOS needs your approval in System Settings → General → Login Items."
                    alert.runModal()
                }
            } catch {
                let alert = NSAlert(); alert.messageText = "Could not change launch at login"
                alert.informativeText = error.localizedDescription; alert.runModal()
            }
        }
        persist(); pulse()
    }
    private func setNotifications(_ enabled: Bool) {
        if !enabled {
            defaults.set(false, forKey: "notificationsEnabled")
            notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationID])
            return
        }
        notificationCenter.requestAuthorization(options: [.alert]) { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.defaults.set(granted, forKey: "notificationsEnabled")
                self.pulse()
                if !granted {
                    let alert = NSAlert(); alert.messageText = "Notifications are off"
                    alert.informativeText = error?.localizedDescription ?? "You can allow Chimpodoro in System Settings → Notifications, then enable notifications here."
                    alert.runModal()
                }
            }
        }
    }
    private func notifyCompletion(_ completion: PomodoroCompletion) {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = completion.phase == .focus ? "Focus complete" : "Break complete"
        content.body = "Your \(completion.phase.title) is complete. " + (engine.isRunning ? "Your \(engine.phase.title) has started." : "Start your \(engine.phase.title) when you’re ready.")
        notificationCenter.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil)) { error in
            if let error { NSLog("Chimpodoro notification: %@", error.localizedDescription) }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in self?.showTimer(); completionHandler() }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
