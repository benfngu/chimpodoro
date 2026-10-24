import AppKit

private final class DesktopSurface: NSView {
    let timer: NSView
    let pin: NSButton
    override var isFlipped: Bool { true }
    init(timer: NSView, pin: NSButton) {
        self.timer=timer;self.pin=pin
        super.init(frame:NSRect(x:0,y:0,width:440,height:730))
        addSubview(timer);addSubview(pin)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    override func layout() {
        super.layout()
        let scale = max(0.8,min(2,min(bounds.width/344,(bounds.height-42)/532)))
        let size=NSSize(width:344*scale,height:532*scale)
        timer.frame=NSRect(x:(bounds.width-size.width)/2,y:max(0,(bounds.height-42-size.height)/2),width:size.width,height:size.height)
        timer.setBoundsSize(NSSize(width:344,height:532))
        pin.frame=NSRect(x:20,y:bounds.height-32,width:220,height:22)
    }
}

final class DesktopTimer: NSWindowController, NSWindowDelegate {
    let timerView = TimerViewController()
    var onVisibilityChange: (() -> Void)?
    private let pin = NSButton(checkboxWithTitle:"Keep above other windows",target:nil,action:nil)
    init(app: AppDelegate) {
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:730),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title="Chimpodoro";window.isReleasedWhenClosed=false;window.contentMinSize=NSSize(width:344,height:574)
        super.init(window:window)
        timerView.owner=app;timerView.isDesktop=true;timerView.loadViewIfNeeded()
        window.contentView=DesktopSurface(timer:timerView.view,pin:pin)
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
    @objc private func togglePin() {window?.level = pin.state == .on ? .floating : .normal}
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
