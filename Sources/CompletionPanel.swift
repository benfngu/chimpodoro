import AppKit
import QuartzCore

/// One persistent, nonmodal completion card; no polling or looping animation.
final class CompletionPanel: NSWindowController {
    var onNext: (() -> Void)?
    private let mark = NSImageView()
    init(phase: PomodoroPhase, next: PomodoroPhase, running: Bool, waitingForHost: Bool = false) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 270), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Chimpodoro"; panel.isReleasedWhenClosed = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        let surface = TimerSurface(frame: NSRect(x: 0, y: 0, width: 360, height: 270))
        panel.contentView = surface
        mark.image = ChimpMark.image(size: 64, resting: next != .focus)
        mark.contentTintColor = .labelColor
        mark.frame = NSRect(x: 148, y: 20, width: 64, height: 64)
        mark.wantsLayer = true; surface.addSubview(mark)
        let title = ChimpStyle.label(phase == .focus ? "Focus complete" : "Break complete", size: 23, weight: .semibold)
        title.alignment = .center; title.frame = NSRect(x: 20, y: 101, width: 320, height: 30); surface.addSubview(title)
        let detail = ChimpStyle.label(running ? "\(next.title.capitalized) started automatically." : "Next: \(next.title).", size: 13)
        detail.alignment = .center; detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 20, y: 141, width: 320, height: 24); surface.addSubview(detail)
        let later = ChimpStyle.button("Dismiss", target: self, action: #selector(dismiss))
        later.frame = NSRect(x: 24, y: 204, width: 112, height: 36); surface.addSubview(later)
        let start = ChimpStyle.button(waitingForHost ? "View party" : running ? "View timer" : "Start \(next.title)", target: self, action: #selector(startNext))
        start.frame = NSRect(x: 145, y: 204, width: 191, height: 36); surface.addSubview(start)
        // No default key: finishing must not intercept the user's typing.
        panel.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        window?.orderFrontRegardless()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, -7, 0, -3, 0]; bounce.duration = 0.55
        mark.layer?.add(bounce, forKey: "completionBounce")
    }
    @objc private func dismiss() { close() }
    @objc private func startNext() { onNext?() }
}
