import AppKit

enum ChimpStyle {
    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        return label
    }
    static func button(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        return button
    }
}

/// A native button with stable contrast even when the full-screen window loses key status.
final class PrimaryTimerButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 18, yRadius: 18)
        let fill = isEnabled ? NSColor.labelColor : NSColor.quaternaryLabelColor
        fill.withAlphaComponent(isHighlighted ? 0.78 : 1).setFill()
        shape.fill()
        let font = NSFont.systemFont(ofSize: bounds.height >= 40 ? 14 : 13, weight: .semibold)
        let text = NSAttributedString(string: title, attributes: [
            .font: font, .foregroundColor: isEnabled ? NSColor.windowBackgroundColor : NSColor.secondaryLabelColor
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        if window?.firstResponder === self && window?.isKeyWindow == true {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            shape.lineWidth = 2; shape.stroke()
        }
    }
}

final class TimerSurface: NSView {
    var onLayout: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); onLayout?() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

/// Static native card drawing: no backing layers, blur, or animation timers.
final class SurfaceCard: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.labelColor.withAlphaComponent(0.025).setFill(); shape.fill()
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        shape.lineWidth = 1; shape.stroke()
    }
}

final class ProgressRing: NSView {
    var progress: Double = 0 { didSet { if progress != oldValue { needsDisplay = true } } }
    var resting = false { didSet { if resting != oldValue { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        let circle = bounds.insetBy(dx: 4, dy: 4)
        let track = NSBezierPath(ovalIn: circle)
        NSColor.controlBackgroundColor.withAlphaComponent(0.45).setFill(); track.fill()
        track.lineWidth = bounds.width > 300 ? 3 : 2
        NSColor.labelColor.withAlphaComponent(0.08).setStroke(); track.stroke()
        if progress > 0 {
            let arc = NSBezierPath()
            arc.lineWidth = track.lineWidth; arc.lineCapStyle = .round
            arc.appendArc(withCenter: NSPoint(x: bounds.midX, y: bounds.midY), radius: circle.width / 2,
                          startAngle: 90, endAngle: 90 - CGFloat(min(1, progress)) * 360, clockwise: true)
            NSColor.labelColor.withAlphaComponent(resting ? 0.45 : 0.85).setStroke(); arc.stroke()
        }
    }
}

final class CycleDots: NSView {
    var completed = 0 { didSet { if completed != oldValue { needsDisplay = true } } }
    var count = 4 { didSet { if count != oldValue { needsDisplay = true } } }
    override func draw(_ dirtyRect: NSRect) {
        let diameter: CGFloat = 5
        let gap: CGFloat = 8
        let width = CGFloat(count) * diameter + CGFloat(max(0, count - 1)) * gap
        for index in 0..<count {
            (index < completed ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.13)).setFill()
            NSBezierPath(ovalIn: NSRect(x: (bounds.width - width) / 2 + CGFloat(index) * (diameter + gap),
                                       y: (bounds.height - diameter) / 2, width: diameter, height: diameter)).fill()
        }
    }
}

final class TimerViewController: NSViewController, NSTextFieldDelegate {
    weak var owner: AppDelegate?
    var isDesktop = false
    let modes = NSSegmentedControl(labels: ["Focus", "Short break", "Long break"], trackingMode: .selectOne, target: nil, action: nil)
    let ring = ProgressRing()
    let mark = NSImageView()
    let time = ChimpStyle.label("25:00", size: 46, weight: .light)
    let caption = ChimpStyle.label("Focus timer", size: 11)
    let dots = CycleDots()
    let task = NSTextField()
    private var taskEdited = false
    private var shownPrimaryTitle: String?
    private var shownTotal: String?
    let total = ChimpStyle.label("Today", size: 11)
    var primary: NSButton!
    var reset: NSButton!
    var skip: NSButton!
    var settings: NSButton!
    var partyButton: NSButton!
    private let wordmark = ChimpStyle.label("Chimpodoro", size: 15, weight: .semibold)
    private let taskLabel = ChimpStyle.label("Focus on", size: 11, weight: .medium)
    private let taskCard = SurfaceCard()
    private let divider = NSBox()
    private var customize: NSButton!
    private var desktop: NSButton!
    private var lastWide: Bool?
    private var lastPhase: PomodoroPhase?
    private let partyStrip = NSView()
    private var stripMembers: [PartyMember] = []
    private var stripResting = false

    override func loadView() {
        view = TimerSurface(frame: NSRect(x: 0, y: 0, width: 344, height: 532))
        wordmark.frame = NSRect(x: 23, y: 22, width: 210, height: 26); view.addSubview(wordmark)
        desktop = NSButton(image:NSImage(systemSymbolName:"macwindow",accessibilityDescription:"Open desktop timer")!,target:self,action:#selector(openDesktop))
        desktop.isBordered=false;desktop.contentTintColor = .secondaryLabelColor
        desktop.frame=NSRect(x:250,y:21,width:30,height:28);desktop.toolTip="Open desktop timer (⌘D)";desktop.isHidden = isDesktop; view.addSubview(desktop)
        settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!, target: self, action: #selector(openSettings))
        settings.isBordered = false; settings.contentTintColor = .secondaryLabelColor
        settings.frame = NSRect(x: 286, y: 21, width: 34, height: 28)
        settings.toolTip = "Settings (⌘,)"; view.addSubview(settings)
        modes.frame = NSRect(x: 22, y: 70, width: 300, height: 28)
        modes.segmentStyle = .capsule
        for index in 0..<3 { modes.setWidth(index == 0 ? 78 : 106, forSegment: index) }
        modes.target = self; modes.action = #selector(selectPhase); view.addSubview(modes)
        ring.frame = NSRect(x: 65, y: 112, width: 214, height: 214); view.addSubview(ring)
        mark.frame = NSRect(x: 142, y: 140, width: 60, height: 60)
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.contentTintColor = .labelColor; view.addSubview(mark)
        time.font = .monospacedDigitSystemFont(ofSize: 48, weight: .light)
        time.alignment = .center; time.frame = NSRect(x: 77, y: 198, width: 190, height: 58); view.addSubview(time)
        caption.alignment = .center; caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 86, y: 261, width: 172, height: 18); view.addSubview(caption)
        dots.frame = NSRect(x: 48, y: 332, width: 248, height: 12); view.addSubview(dots)
        taskCard.frame = NSRect(x: 23, y: 350, width: 298, height: 36)
        view.addSubview(taskCard)
        taskLabel.textColor = .secondaryLabelColor
        taskLabel.frame = NSRect(x: 35, y: 362, width: 36, height: 14); view.addSubview(taskLabel)
        task.placeholderString = "What are you working on?"
        task.stringValue = owner?.taskName ?? ""
        task.isBordered = false; task.drawsBackground = false; task.focusRingType = .none
        task.font = .systemFont(ofSize: 12); task.alignment = .left
        task.setAccessibilityLabel("Focus task, optional")
        task.frame = NSRect(x: 79, y: 359, width: 230, height: 23)
        task.delegate = self; view.addSubview(task)
        primary = PrimaryTimerButton(title: "Start focus", target: self, action: #selector(toggle))
        primary.frame = NSRect(x: 23, y: 399, width: 194, height: 36)
        primary.bezelColor = .labelColor; primary.contentTintColor = .windowBackgroundColor
        primary.keyEquivalent = " "; primary.keyEquivalentModifierMask = []
        primary.toolTip = "Start or pause (Space)"; view.addSubview(primary)
        reset = NSButton(image: NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: "Reset timer")!, target: self, action: #selector(resetTimer))
        reset.isBordered = false; reset.contentTintColor = .secondaryLabelColor
        reset.frame = NSRect(x: 225, y: 399, width: 44, height: 36)
        reset.toolTip = "Reset this timer (⌘R)"; view.addSubview(reset)
        skip = NSButton(image: NSImage(systemSymbolName: "forward.end", accessibilityDescription: "Skip to next session")!, target: self, action: #selector(skipTimer))
        skip.isBordered = false; skip.contentTintColor = .secondaryLabelColor
        skip.frame = NSRect(x: 277, y: 399, width: 44, height: 36)
        skip.toolTip = "Skip this session (⌘→). Skipped focus sessions are not counted."; view.addSubview(skip)
        divider.frame = NSRect(x: 23, y: 445, width: 298, height: 1); divider.boxType = .separator; view.addSubview(divider)
        total.frame = NSRect(x: 20, y: 461, width: 304, height: 18)
        total.alignment = .center; total.textColor = .secondaryLabelColor; view.addSubview(total)
        partyStrip.frame=NSRect(x:25,y:453,width:294,height:32);view.addSubview(partyStrip)
        partyButton = ChimpStyle.button("Create / join party…", target:self, action:#selector(openParty))
        partyButton.isBordered = true; partyButton.font = .systemFont(ofSize: 12, weight: .medium)
        partyButton.contentTintColor = .secondaryLabelColor
        customize = ChimpStyle.button("Customize chimp…", target: self, action: #selector(customizeChimp))
        customize.font = .systemFont(ofSize: 12, weight: .medium)
        customize.frame = NSRect(x: 23, y: 490, width: 143, height: 28)
        view.addSubview(customize)
        partyButton.frame = NSRect(x:174,y:490,width:147,height:28); view.addSubview(partyButton)
        // Only the small mascot is layer-backed. No full-window raster surfaces.
        mark.wantsLayer = true
        (view as? TimerSurface)?.onLayout = { [weak self] in self?.layoutContents() }
        layoutContents()
    }

    private func layoutContents() {
        guard primary != nil else { return }
        let width = view.bounds.width, height = view.bounds.height
        let wide = isDesktop && width >= 780 && height >= 440
        wordmark.isHidden = isDesktop
        desktop.isHidden = isDesktop
        taskCard.isHidden = isDesktop
        let dial: NSRect
        if wide {
            // Cap the content width so controls remain within easy reach on large displays.
            let contentWidth = min(width - 96, 1160)
            let controlWidth: CGFloat = 310
            let gap: CGFloat = 72
            let diameter = min(contentWidth - controlWidth - gap, height - 140, 640)
            let left = (width - (diameter + gap + controlWidth)) / 2
            dial = NSRect(x: left, y: (height - diameter) / 2 - 14, width: diameter, height: diameter)
            let x = dial.maxX + gap, y = (height - 360) / 2
            modes.frame = NSRect(x: x, y: y, width: controlWidth, height: 30)
            taskLabel.frame = NSRect(x: x + 2, y: y + 64, width: controlWidth, height: 18)
            task.frame = NSRect(x: x + 2, y: y + 90, width: controlWidth - 4, height: 30)
            task.font = .systemFont(ofSize: 18, weight: .regular)
            primary.frame = NSRect(x: x, y: y + 148, width: controlWidth - 104, height: 42)
            reset.frame = NSRect(x: x + controlWidth - 96, y: y + 148, width: 42, height: 42)
            skip.frame = NSRect(x: x + controlWidth - 46, y: y + 148, width: 42, height: 42)
            divider.frame = NSRect(x: x, y: y + 216, width: controlWidth, height: 1)
            total.frame = NSRect(x: x, y: y + 240, width: controlWidth, height: 24)
            partyStrip.frame = NSRect(x: x, y: y + 235, width: controlWidth, height: 32)
            customize.frame = NSRect(x: x, y: y + 296, width: 148, height: 32)
            partyButton.frame = NSRect(x: x + 158, y: y + 296, width: 152, height: 32)
            dots.frame = NSRect(x: dial.minX, y: dial.maxY + 25, width: diameter, height: 12)
            settings.frame = NSRect(x: width - 54, y: 16, width: 32, height: 28)
        } else {
            let column: CGFloat = isDesktop ? min(360, width - 48) : 298
            let x = (width - column) / 2
            let diameter: CGFloat = isDesktop ? min(320, max(214, height - 328)) : 214
            let top: CGFloat = isDesktop ? max(54, (height - (diameter + 290)) / 2) : 70
            modes.frame = NSRect(x: x, y: top, width: column, height: 28)
            dial = NSRect(x: (width - diameter) / 2, y: top + 42, width: diameter, height: diameter)
            dots.frame = NSRect(x: x, y: dial.maxY + 8, width: column, height: 12)
            let taskY = dial.maxY + 32
            taskCard.frame = NSRect(x: x, y: taskY - 8, width: column, height: 38)
            taskLabel.frame = NSRect(x: x + 12, y: taskY + 3, width: 50, height: 17)
            task.frame = NSRect(x: x + 70, y: taskY, width: column - 82, height: 25)
            task.font = .systemFont(ofSize: 12)
            let actionY = taskY + 42
            primary.frame = NSRect(x: x, y: actionY, width: column - 104, height: 38)
            reset.frame = NSRect(x: x + column - 96, y: actionY, width: 44, height: 38)
            skip.frame = NSRect(x: x + column - 44, y: actionY, width: 44, height: 38)
            divider.frame = NSRect(x: x, y: actionY + 50, width: column, height: 1)
            total.frame = NSRect(x: x, y: actionY + 65, width: column, height: 20)
            partyStrip.frame = NSRect(x: x, y: actionY + 58, width: column, height: 32)
            customize.frame = NSRect(x: x, y: actionY + 98, width: (column - 8) / 2, height: 28)
            partyButton.frame = NSRect(x: x + (column + 8) / 2, y: actionY + 98, width: (column - 8) / 2, height: 28)
            settings.frame = NSRect(x: width - 58, y: isDesktop ? 8 : 21, width: 34, height: 28)
        }
        for index in 0..<3 { modes.setWidth((modes.frame.width - 10) / 3, forSegment: index) }
        ring.frame = dial
        let scale = dial.width / 214
        let mascot = min(112, 60 * scale)
        mark.frame = NSRect(x: dial.midX - mascot / 2, y: dial.minY + dial.height * 0.13, width: mascot, height: mascot)
        let fontSize = min(112, 48 * scale)
        time.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .light)
        time.frame = NSRect(x: dial.minX + 10, y: dial.minY + dial.height * 0.40, width: dial.width - 20, height: fontSize * 1.3)
        caption.font = .systemFont(ofSize: wide ? 14 : 11, weight: .medium)
        caption.frame = NSRect(x: dial.minX + 16, y: dial.minY + dial.height * 0.73, width: dial.width - 32, height: 22)
        layoutRoster()
        if let previous = lastWide, previous != wide { animateMascot() }
        lastWide = wide
    }

    private func layoutRoster() {
        let start = (partyStrip.bounds.width - CGFloat(partyStrip.subviews.count) * 34) / 2
        for (index, avatar) in partyStrip.subviews.enumerated() {
            avatar.frame = NSRect(x: start + CGFloat(index) * 34, y: 0, width: 30, height: 30)
        }
    }

    private func animateMascot() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              view.window?.isVisible == true, !view.inLiveResize else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.35; fade.toValue = 1; fade.duration = 0.22
        mark.layer?.add(fade, forKey: "phaseTransition")
    }

    func render(_ engine: Pomodoro, at now: Date) {
        loadViewIfNeeded()
        if task.currentEditor() == nil { task.stringValue = owner?.taskName ?? "" }
        if let previous = lastPhase, previous != engine.phase { animateMascot() }
        lastPhase = engine.phase
        modes.selectedSegment = engine.phase == .focus ? 0 : engine.phase == .shortBreak ? 1 : 2
        let seconds = Int(ceil(engine.remaining(at: now)))
        time.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        time.setAccessibilityLabel("\(seconds / 60) minutes, \(seconds % 60) seconds remaining")
        ring.progress = engine.progress(at: now); ring.resting = engine.phase != .focus
        mark.contentTintColor = nil
        mark.image = owner?.chimpImages[engine.phase == .focus ? 0 : 1]
        caption.stringValue = engine.isPaused ? "Paused" : engine.isRunning ? "In progress" : "Ready"
        dots.completed = engine.completedFocusesInCycle; dots.count = engine.settings.longBreakInterval
        dots.setAccessibilityElement(true)
        dots.setAccessibilityLabel("\(engine.completedFocusesInCycle) of \(engine.settings.longBreakInterval) focus sessions this cycle")
        let primaryTitle = engine.isRunning ? "Pause" : engine.isPaused ? "Resume" : engine.phase == .focus ? "Start focus" : "Start break"
        let canControl = owner?.party.joined != true || owner?.party.canControl == true
        if shownPrimaryTitle != primaryTitle {
            shownPrimaryTitle = primaryTitle
            primary.title = primaryTitle
        }
        primary.isEnabled = canControl; reset.isEnabled = canControl; skip.isEnabled = canControl; modes.isEnabled = canControl
        if let party = owner?.party, party.joined {
            caption.stringValue = !party.connected ? "Reconnecting…" : engine.remaining(at:now) <= 0 ? "Synchronizing…" : party.isHost ? "Party · hosting" : "Party · synced"
            partyButton.title = "View party · \(party.state?.members.count ?? 1)"
        } else { partyButton.title = "Create / join party…" }
        let today = engine.todayStats(at: now)
        let totalText = "Today  ·  \(today.completedFocuses) \(today.completedFocuses == 1 ? "session" : "sessions")  ·  \(today.focusedMinutes) min"
        if shownTotal != totalText {
            shownTotal = totalText
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            let styled = NSMutableAttributedString(string: totalText, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph])
            for value in ["\(today.completedFocuses)", "\(today.focusedMinutes)"] {
                styled.addAttributes([.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor], range: (totalText as NSString).range(of: value))
            }
            total.attributedStringValue = styled
        }
        let members = owner?.party.state?.members ?? []
        let resting = engine.phase != .focus
        partyStrip.isHidden = owner?.party.joined != true
        total.isHidden = owner?.party.joined == true
        if members != stripMembers || resting != stripResting {
            stripMembers = members; stripResting = resting
            partyStrip.subviews.forEach { $0.removeFromSuperview() }
            let start = (partyStrip.bounds.width-CGFloat(members.count)*34)/2
            for (index, member) in members.enumerated() {
                let image=NSImageView(frame:NSRect(x:start+CGFloat(index)*34,y:0,width:30,height:30))
                image.image=ChimpAvatar.image(member.profile,size:30,resting:resting)
                image.alphaValue=member.online ? 1 : 0.35
                image.toolTip=member.profile.name + (member.online ? "" : " · offline")
                partyStrip.addSubview(image)
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === task,
              commandSelector == #selector(NSResponder.insertNewline(_:)) ||
              commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        // End editing without forwarding Return/Escape into timer or window actions.
        view.window?.makeFirstResponder(view)
        return true
    }

    func controlTextDidChange(_ obj: Notification) { taskEdited = true }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard taskEdited else { return }; taskEdited = false
        let trimmed = String(task.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160))
        task.stringValue = trimmed; owner?.taskName = trimmed
    }
    @objc func toggle() { view.window?.makeFirstResponder(view); owner?.toggleTimer() }
    @objc func resetTimer() { owner?.resetTimer() }
    @objc func skipTimer() { owner?.skipTimer() }
    @objc func selectPhase() { owner?.selectPhase([.focus, .shortBreak, .longBreak][modes.selectedSegment]) }
    @objc func openSettings() { owner?.showSettings() }
    @objc func openDesktop() { owner?.showDesktop() }
    @objc func openParty() { owner?.showParty() }
    @objc func customizeChimp() { owner?.showChimpCustomization() }
}

final class SettingsController: NSWindowController {
    weak var appDelegate: AppDelegate?
    var fields: [NSTextField] = []
    var checks: [NSButton] = []
    let notice = ChimpStyle.label("", size: 11)

    init(owner: AppDelegate) {
        self.appDelegate = owner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 526), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Chimpodoro Settings"; window.isReleasedWhenClosed = false
        super.init(window: window)
        let content = TimerSurface(frame: NSRect(x: 0, y: 0, width: 410, height: 526)); window.contentView = content
        let title = ChimpStyle.label("Timer settings", size: 20, weight: .semibold)
        title.frame = NSRect(x: 24, y: 22, width: 362, height: 28); content.addSubview(title)
        let subtitle = ChimpStyle.label("Durations and behavior", size: 12)
        subtitle.textColor = .secondaryLabelColor; subtitle.frame = NSRect(x: 24, y: 54, width: 362, height: 20); content.addSubview(subtitle)
        for (index, text) in ["Focus", "Short break", "Long break", "Long break after"].enumerated() {
            let y = CGFloat(95 + index * 35)
            let label = ChimpStyle.label(text, size: 13)
            label.frame = NSRect(x: 25, y: y + 3, width: 185, height: 21); content.addSubview(label)
            let field = NSTextField(frame: NSRect(x: 231, y: y, width: 60, height: 25))
            field.alignment = .right; field.setAccessibilityLabel(text)
            content.addSubview(field); fields.append(field)
            let unit = ChimpStyle.label(index == 3 ? "sessions" : "minutes", size: 12)
            unit.textColor = .secondaryLabelColor; unit.frame = NSRect(x: 301, y: y + 4, width: 82, height: 19); content.addSubview(unit)
        }
        for (index, text) in ["Start breaks automatically", "Start focus automatically", "Play a gentle completion sound", "Show completion notifications", "Launch at login"].enumerated() {
            let check = NSButton(checkboxWithTitle: text, target: nil, action: nil)
            check.frame = NSRect(x: 23, y: CGFloat(254 + index * 31), width: 363, height: 22)
            content.addSubview(check); checks.append(check)
        }
        checks[2].frame.size.width = 275
        let preview = ChimpStyle.button("Test sound", target: self, action: #selector(testSound))
        preview.frame = NSRect(x: 300, y: 312, width: 87, height: 28)
        content.addSubview(preview)
        notice.stringValue = "Duration changes apply to the next fresh timer."
        notice.textColor = .secondaryLabelColor
        notice.frame = NSRect(x: 25, y: 422, width: 363, height: 18); content.addSubview(notice)
        let cancel = ChimpStyle.button("Cancel", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"; cancel.frame = NSRect(x: 182, y: 469, width: 91, height: 32); content.addSubview(cancel)
        let save = ChimpStyle.button("Save", target: self, action: #selector(save))
        save.keyEquivalent = "\r"; save.frame = NSRect(x: 282, y: 469, width: 104, height: 32); content.addSubview(save)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() {
        guard let owner = appDelegate else { return }
        let settings = owner.engine.settings
        fields.forEach { $0.isEnabled = !owner.party.joined }
        checks.prefix(2).forEach { $0.isEnabled = !owner.party.joined }
        notice.stringValue = owner.party.joined ? "Party durations are set when the host creates it." : "Duration changes apply to the next fresh timer."
        for (index, value) in [settings.focusMinutes, settings.shortBreakMinutes, settings.longBreakMinutes, settings.longBreakInterval].enumerated() { fields[index].integerValue = value }
        for (index, value) in [settings.autoStartBreaks, settings.autoStartFocus, owner.soundEnabled, owner.notificationsEnabled, owner.launchAtLogin].enumerated() { checks[index].state = value ? .on : .off }
    }
    @objc func testSound() {
        guard let owner = appDelegate else { return }
        notice.stringValue = owner.previewCompletionSound()
            ? "Playing chime. Check your Mac’s volume and audio output."
            : "Could not play the chime. Try reopening Chimpodoro."
    }
    @objc func cancel() { close() }
    @objc func save() {
        guard let owner = appDelegate else { return }
        let ranges = [1...180, 1...60, 1...120, 1...12]
        var values: [Int] = []
        for (index, field) in fields.enumerated() {
            guard let value = Int(field.stringValue), ranges[index].contains(value) else {
                let alert = NSAlert(); alert.messageText = "Choose a value from \(ranges[index].lowerBound) to \(ranges[index].upperBound)."
                alert.informativeText = index == 3 ? "This is the number of completed focus sessions before a long break." : "Timer lengths are whole minutes."
                if let window { alert.beginSheetModal(for: window) }
                return
            }
            values.append(value)
        }
        owner.applySettings(PomodoroSettings(focusMinutes: values[0], shortBreakMinutes: values[1], longBreakMinutes: values[2], longBreakInterval: values[3], autoStartBreaks: checks[0].state == .on, autoStartFocus: checks[1].state == .on), sound: checks[2].state == .on, notifications: checks[3].state == .on, login: checks[4].state == .on)
        close()
    }
}
