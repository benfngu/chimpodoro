import AppKit

enum ChimpAvatar {
    static func image(_ profile: ChimpProfile, size: CGFloat = 48, resting: Bool = false) -> NSImage {
        let colors: [String:NSColor] = ["ink":.labelColor, "sage":NSColor(srgbRed:0.25,green:0.48,blue:0.35,alpha:1), "blue":.systemBlue, "rose":.systemPink, "gold":.systemOrange]
        let color = colors[profile.color] ?? .labelColor
        let image = NSImage(size: NSSize(width:size,height:size), flipped:false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            // Isolate cutouts so they reveal the actual surface beneath the avatar.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { context.endTransparencyLayer() }
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ChimpMark.draw(in: rect.insetBy(dx:size*0.06,dy:size*0.06), color:color, resting:resting)
            NSGraphicsContext.saveGraphicsState(); defer {NSGraphicsContext.restoreGraphicsState()}
            let transform = NSAffineTransform(); transform.scale(by:size/100); transform.concat()
            color.setStroke(); color.setFill()
            if profile.accessory == "glasses" {
                // Measured from ChimpRead Assets/PaperShelf.png (1280px):
                // retain frame aspect, corner radii, bridge and temple lengths.
                // Align its pupil centers (493, 533), (758, 533) to our face.
                let scale: CGFloat = 19.25 / 265
                let glassesTransform = NSAffineTransform()
                glassesTransform.translateX(by: 40.375 - 493*scale,
                                             yBy: 59.625 - 747*scale)
                // ChimpRead's smaller pupils leave breathing room inside the lenses.
                if !resting {
                    color.setFill()
                    for x in [CGFloat(40.375), CGFloat(59.625)] {
                        NSBezierPath(ovalIn: NSRect(x: x-4.1, y: 59.625-4.1, width: 8.2, height: 8.2)).fill()
                    }
                    if dark { context.setBlendMode(.clear) }
                    NSColor.white.setFill()
                    let diameter = 76*scale
                    for x in [CGFloat(40.375), CGFloat(59.625)] {
                        NSBezierPath(ovalIn: NSRect(x: x-diameter/2, y: 59.625-diameter/2, width: diameter, height: diameter)).fill()
                    }
                }
                glassesTransform.scale(by: scale); glassesTransform.concat()
                if dark { context.setBlendMode(.clear) }
                NSColor.white.setStroke()
                for x in [CGFloat(380), CGFloat(671)] {
                    let frame = NSBezierPath(roundedRect: NSRect(x: x, y: 692, width: 201, height: 133),
                                             xRadius: 38, yRadius: 38)
                    frame.lineWidth = 24; frame.stroke()
                }
                let connections = NSBezierPath()
                for (start, end) in [(CGFloat(327), CGFloat(380)), (CGFloat(581), CGFloat(671)), (CGFloat(872), CGFloat(925))] {
                    connections.move(to: NSPoint(x: start, y: 775))
                    connections.line(to: NSPoint(x: end, y: 775))
                }
                connections.lineWidth = 24; connections.lineCapStyle = .round; connections.stroke()
            } else if profile.accessory == "crown" {
                let crown=NSBezierPath();crown.move(to:NSPoint(x:36,y:87));crown.line(to:NSPoint(x:33,y:99));crown.line(to:NSPoint(x:44,y:94));crown.line(to:NSPoint(x:50,y:100));crown.line(to:NSPoint(x:56,y:94));crown.line(to:NSPoint(x:67,y:99));crown.line(to:NSPoint(x:64,y:87));crown.close();crown.fill()
            } else if profile.accessory == "bow" {
                let bow=NSBezierPath();bow.move(to:NSPoint(x:39,y:23));bow.line(to:NSPoint(x:39,y:14));bow.line(to:NSPoint(x:61,y:23));bow.line(to:NSPoint(x:61,y:14));bow.close();bow.fill()
            }
            return true
        }
        image.accessibilityDescription = "\(profile.name)’s chimp, \(profile.color), \(profile.accessory)"
        return image
    }
}

final class PartyWindow: NSWindowController {
    private weak var appDelegate: AppDelegate?
    private let name = NSTextField()
    private let colors = NSPopUpButton()
    private let accessories = NSPopUpButton()
    private let preview = NSImageView()
    private let code = NSTextField()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let invite = ChimpStyle.label("",size:18,weight:.semibold)
    private let roster = TimerSurface()
    private var shownProfile: ChimpProfile?
    private var shownMembers: [PartyMember] = []
    private var shownHost: String?
    private var shownResting = false
    private var expanded: Bool?
    private var serviceButton: NSButton!
    private var createButton: NSButton!
    private var joinButton: NSButton!
    private var leaveButton: NSButton!
    private var reconnectButton: NSButton!
    private var copyButton: NSButton!
    private let colorKeys = ["ink","sage","blue","rose","gold"]
    private let accessoryKeys = ["none","glasses","crown","bow"]
    init(app: AppDelegate) {
        appDelegate = app
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:470,height:640),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title = "Chimpodoro Party";window.isReleasedWhenClosed = false
        super.init(window:window)
        let surface = TimerSurface(frame:NSRect(x:0,y:0,width:470,height:640));window.contentView=surface
        func label(_ text:String,_ frame:NSRect) {let view=ChimpStyle.label(text,size:12);view.frame=frame;surface.addSubview(view)}
        surface.addSubview(SurfaceCard(frame: NSRect(x: 20, y: 16, width: 430, height: 162)))
        surface.addSubview(SurfaceCard(frame: NSRect(x: 20, y: 194, width: 430, height: 150)))
        preview.frame=NSRect(x:30,y:43,width:108,height:108);surface.addSubview(preview)
        let heading = ChimpStyle.label("Your chimp", size: 18, weight: .semibold)
        heading.frame=NSRect(x:154,y:28,width:280,height:25);surface.addSubview(heading)
        let partyHeading = ChimpStyle.label("Party", size: 18, weight: .semibold)
        partyHeading.frame=NSRect(x:32,y:207,width:100,height:25);surface.addSubview(partyHeading)
        label("One timer · up to 8 chimps", NSRect(x:184,y:213,width:250,height:18))
        name.frame=NSRect(x:154,y:62,width:280,height:25);name.stringValue=app.party.profile.name;name.placeholderString="Display name";name.setAccessibilityLabel("Display name");surface.addSubview(name)
        colors.addItems(withTitles:["Ink","Sage","Blue","Rose","Gold"]);colors.selectItem(at:colorKeys.firstIndex(of:app.party.profile.color) ?? 0)
        accessories.addItems(withTitles:["No accessory","Glasses","Crown","Bow"]);accessories.selectItem(at:accessoryKeys.firstIndex(of:app.party.profile.accessory) ?? 0)
        colors.frame=NSRect(x:153,y:99,width:128,height:26);accessories.frame=NSRect(x:290,y:99,width:146,height:26)
        colors.target=self;colors.action = #selector(saveProfile); accessories.target=self;accessories.action = #selector(saveProfile)
        surface.addSubview(colors);surface.addSubview(accessories)
        let save=ChimpStyle.button("Save chimp",target:self,action:#selector(saveProfile));save.frame=NSRect(x:310,y:136,width:126,height:30);surface.addSubview(save)
        createButton=ChimpStyle.button("Create party",target:self,action:#selector(create));createButton.frame=NSRect(x:30,y:250,width:136,height:32);surface.addSubview(createButton)
        code.frame=NSRect(x:180,y:254,width:148,height:25);code.placeholderString="Join code";code.setAccessibilityLabel("Join code");surface.addSubview(code)
        joinButton=ChimpStyle.button("Join",target:self,action:#selector(join));joinButton.frame=NSRect(x:342,y:250,width:96,height:32);surface.addSubview(joinButton)
        invite.frame=NSRect(x:30,y:365,width:270,height:28);surface.addSubview(invite)
        copyButton=ChimpStyle.button("Copy code",target:self,action:#selector(copyCode));copyButton.frame=NSRect(x:322,y:361,width:120,height:32);surface.addSubview(copyButton)
        status.font = .systemFont(ofSize:12);status.textColor = .secondaryLabelColor;status.frame=NSRect(x:32,y:296,width:404,height:38);surface.addSubview(status)
        roster.frame=NSRect(x:24,y:410,width:422,height:196);surface.addSubview(roster)
        leaveButton=ChimpStyle.button("Leave party",target:self,action:#selector(leave));leaveButton.frame=NSRect(x:24,y:594,width:130,height:32);surface.addSubview(leaveButton)
        reconnectButton=ChimpStyle.button("Reconnect",target:self,action:#selector(reconnect));reconnectButton.frame=NSRect(x:166,y:594,width:128,height:32);surface.addSubview(reconnectButton)
        let service=ChimpStyle.button("Service…",target:self,action:#selector(configureService));service.frame=NSRect(x:322,y:594,width:120,height:32);surface.addSubview(service)
        service.isBordered = false; service.font = .systemFont(ofSize: 11); service.contentTintColor = .secondaryLabelColor
        serviceButton = service
        window.center();refresh()
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    func focusCustomization() { window?.makeFirstResponder(name); name.selectText(nil) }
    func refresh() {
        guard let party=appDelegate?.party else {return}
        if shownProfile != party.profile {
            shownProfile = party.profile
            preview.image=ChimpAvatar.image(party.profile,size:108)
        }
        if expanded != party.joined {
            expanded = party.joined
            let height: CGFloat = party.joined ? 650 : 404
            if let window {
                let top = window.frame.maxY
                window.setContentSize(NSSize(width: 470, height: height))
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top-window.frame.height))
            }
            serviceButton.frame.origin.y = height-56
            roster.isHidden = !party.joined
        }
        createButton.isEnabled = !party.joined && !party.busy;joinButton.isEnabled=createButton.isEnabled;code.isEnabled=createButton.isEnabled
        leaveButton.isHidden = !party.joined;leaveButton.title=party.isHost ? "End party":"Leave party"
        reconnectButton.isHidden = !party.joined || party.connected
        invite.isHidden = !party.joined
        copyButton.isHidden = !party.joined
        invite.stringValue=party.membership.map {"Party · \($0.code)"} ?? "Up to 8 chimps"
        status.stringValue=party.endpoint.isEmpty ? "Set up the party service to connect across the internet." : party.message
        let members = party.state?.members ?? []
        let resting = party.state?.phase != .focus
        guard members != shownMembers || shownHost != party.state?.host || resting != shownResting else { return }
        shownMembers = members; shownHost = party.state?.host; shownResting = resting
        roster.subviews.forEach {$0.removeFromSuperview()}
        for (index,member) in (party.state?.members ?? []).enumerated() {
            let x=CGFloat(index%2)*211,y=CGFloat(index/2)*48
            let avatar=NSImageView(frame:NSRect(x:x,y:y,width:38,height:38));avatar.image=ChimpAvatar.image(member.profile,size:38,resting:party.state?.phase != .focus);roster.addSubview(avatar)
            let title=ChimpStyle.label(member.profile.name,size:12,weight:.medium);title.frame=NSRect(x:x+46,y:y+1,width:158,height:18);title.lineBreakMode = .byTruncatingTail;roster.addSubview(title)
            let detail=ChimpStyle.label((member.id==party.state?.host ? "Host · ":"")+(member.online ? "Connected":"Offline"),size:10);detail.textColor = .secondaryLabelColor;detail.frame=NSRect(x:x+46,y:y+21,width:158,height:16);roster.addSubview(detail)
        }
    }
    @objc private func saveProfile() {
        guard let party=appDelegate?.party else {return}
        let text=String(name.stringValue.trimmingCharacters(in:.whitespacesAndNewlines).filter {!$0.isNewline}.prefix(24))
        name.stringValue=text.isEmpty ? "Chimp":text
        party.profile=ChimpProfile(name:name.stringValue,color:colorKeys[colors.indexOfSelectedItem],accessory:accessoryKeys[accessories.indexOfSelectedItem]);party.updateProfile();refresh()
    }
    @objc private func create() {saveProfile();guard let app=appDelegate else{return};app.party.join(code:nil,settings:app.soloSettings)}
    @objc private func join() {saveProfile();guard let app=appDelegate else{return};app.party.join(code:code.stringValue,settings:app.soloSettings)}
    @objc private func copyCode() {guard let code=appDelegate?.party.membership?.code else{return};NSPasteboard.general.clearContents();NSPasteboard.general.setString(code,forType:.string)}
    @objc private func reconnect() {appDelegate?.party.reconnectNow()}
    @objc private func leave() {
        guard let party=appDelegate?.party else{return}
        if party.isHost {
            let alert=NSAlert();alert.messageText="End the party for everyone?";alert.informativeText="Everyone returns to their own solo timer.";alert.addButton(withTitle:"End party");alert.addButton(withTitle:"Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else{return}
        }
        party.leave()
    }
    @objc private func configureService() {
        guard let party=appDelegate?.party else{return}
        let alert=NSAlert();alert.messageText="Party service";alert.informativeText=party.joined ? "Leave the party before changing its service." : "Use the HTTPS address from your Cloudflare deployment. Everyone must use the same service."
        if party.joined {alert.runModal();return}
        let field=NSTextField(frame:NSRect(x:0,y:0,width:340,height:26));field.stringValue=party.endpoint;field.placeholderString="https://chimpodoro-party.example.workers.dev"
        alert.accessoryView=field;alert.addButton(withTitle:"Save");alert.addButton(withTitle:"Cancel")
        if alert.runModal() == .alertFirstButtonReturn {party.endpoint=field.stringValue;refresh()}
    }
}
