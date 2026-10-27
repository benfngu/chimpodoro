import AppKit

private final class DesktopSurface: NSView {
    let timer: NSView
    let pin: NSButton
    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(timer) }
    init(timer: NSView, pin: NSButton) {
        self.timer=timer;self.pin=pin
        super.init(frame:NSRect(x:0,y:0,width:440,height:730))
        addSubview(timer);addSubview(pin)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func layout() {
        super.layout()
        timer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 42))
        timer.needsLayout = true
        pin.frame=NSRect(x:20,y:bounds.height-32,width:220,height:22)
    }
}

final class DesktopTimer: NSWindowController, NSWindowDelegate {
    let timerView = TimerViewController()
    var onVisibilityChange: (() -> Void)?
    private let pin = NSButton(checkboxWithTitle:"Keep above other windows",target:nil,action:nil)
    init(app: AppDelegate) {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:920,height:640),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Chimpodoro";window.isReleasedWhenClosed=false;window.contentMinSize=NSSize(width:344,height:574)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        super.init(window:window)
        timerView.owner=app;timerView.isDesktop=true;timerView.loadViewIfNeeded()
        window.contentView=DesktopSurface(timer:timerView.view,pin:pin)
        window.initialFirstResponder = timerView.view
        window.delegate=self
        window.setFrameAutosaveName("ChimpodoroDesktop")
        pin.font = .systemFont(ofSize: 11); pin.contentTintColor = .secondaryLabelColor
        pin.target=self;pin.action = #selector(togglePin)
        if !window.setFrameUsingName("ChimpodoroDesktop") {window.center()}
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func present() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps:true)
        window?.deminiaturize(nil);showWindow(nil);window?.makeKeyAndOrderFront(nil)
        onVisibilityChange?()
    }
    func moveToOtherDisplay() {
        guard let window, !window.styleMask.contains(.fullScreen), NSScreen.screens.count > 1 else { return }
        let screens = NSScreen.screens
        let current = screens.firstIndex { $0 == window.screen } ?? 0
        let available = screens[(current + 1) % screens.count].visibleFrame
        let size = NSSize(width: min(window.frame.width, available.width), height: min(window.frame.height, available.height))
        let frame = NSRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height)
        window.setFrame(frame, display: true)
    }
    @objc private func togglePin() {
        guard window?.styleMask.contains(.fullScreen) != true else { return }
        window?.level = pin.state == .on ? .floating : .normal
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.level = .normal
        pin.isEnabled = false
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        pin.isEnabled = true
        togglePin()
        onVisibilityChange?()
    }
    func windowDidEnterFullScreen(_ notification: Notification) { onVisibilityChange?() }
    func windowWillClose(_ notification:Notification) {
        UserDefaults.standard.set(false,forKey:"desktopOpen")
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in self?.onVisibilityChange?() }
    }
    func windowDidMiniaturize(_ notification:Notification) {onVisibilityChange?()}
    func windowDidDeminiaturize(_ notification:Notification) {onVisibilityChange?()}
    func windowDidChangeOcclusionState(_ notification:Notification) {onVisibilityChange?()}
    var visible: Bool { window?.isVisible == true && window?.isMiniaturized == false && window?.occlusionState.contains(.visible) == true }
}
