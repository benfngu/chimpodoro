import Foundation

struct ChimpProfile: Codable, Equatable {
    var name = "Chimp"
    var color = "ink"
    var accessory = "none"
}
struct PartyMember: Codable, Equatable {
    let id: String
    let profile: ChimpProfile
    let online: Bool
}
struct PartyCompletion: Codable { let id: Int; let phase: PomodoroPhase; let at: Double }
struct PartyState: Codable {
    let code: String
    let host: String
    let revision: Int
    let settings: PomodoroSettings
    let phase: PomodoroPhase
    let duration: Double
    let remaining: Double
    let deadline: Double?
    let started: Bool
    let cycle: Int
    let completion: PartyCompletion?
    let serverTime: Double
    let expires: Double
    let members: [PartyMember]
    var timer: Pomodoro { Pomodoro.partyView(settings: settings, phase: phase, duration: duration, remaining: remaining, deadline: deadline, started: started, cycle: cycle) }
}
struct PartyMembership: Codable { let code: String; let id: String; let token: String }

/// One system WebSocket while joined; no network work in solo mode.
final class PartyClient: NSObject, URLSessionTaskDelegate {
    var onChange: (() -> Void)?
    var onCompletion: ((PartyCompletion) -> Void)?
    var onJoined: (() -> Void)?
    var onLeft: (() -> Void)?
    private(set) var state: PartyState?
    private(set) var membership: PartyMembership?
    private(set) var connected = false
    private(set) var busy = false
    private(set) var message = "Create a party or enter a join code."
    var profile: ChimpProfile {
        didSet { if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "chimpProfile") } }
    }
    var endpoint: String {
        get {
            let override = UserDefaults.standard.string(forKey: "partyEndpoint")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return override.isEmpty ? Bundle.main.object(forInfoDictionaryKey: "PartyServiceURL") as? String ?? "" : override
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "partyEndpoint") }
    }
    var joined: Bool { membership != nil }
    var isHost: Bool { membership?.id == state?.host && membership != nil }
    var canControl: Bool { connected && isHost }
    private var socket: URLSessionWebSocketTask?
    private var request: URLSessionDataTask?
    private var reconnect: DispatchWorkItem?
    private var heartbeat: Timer?
    private var session: URLSession!
    private var generation = 0
    private var retry = 0
    private var serverError: String?
    private var clockDate = Date()
    private var clockUptime = ProcessInfo.processInfo.systemUptime
    private var lastCompletion: Int?
    private var receivedInitial = false
    private var service: URL?
    var now: Date { clockDate.addingTimeInterval(ProcessInfo.processInfo.systemUptime - clockUptime) }

    override init() {
        profile = UserDefaults.standard.data(forKey: "chimpProfile").flatMap { try? JSONDecoder().decode(ChimpProfile.self, from: $0) } ?? ChimpProfile()
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate:self, delegateQueue:nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func restore() {
        guard let saved = PartyCredentials.load(), let url = URL(string:saved.endpoint), url.scheme == "https" else { return }
        service = url; membership = saved.membership; onJoined?(); connect()
    }
    func shutdown() {
        generation += 1
        reconnect?.cancel(); reconnect = nil
        heartbeat?.invalidate(); heartbeat = nil
        request?.cancel(); request = nil
        let previous = socket; socket = nil
        previous?.cancel(with:.goingAway,reason:nil)
        session.invalidateAndCancel()
    }
    func join(code: String?, settings: PomodoroSettings) {
        guard !joined && !busy else { return }
        guard let url = URL(string: endpoint), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            message = "Set the HTTPS party service address first."; onChange?(); return
        }
        let cleanCode = code?.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if let code = cleanCode, code.count != 10 || code.range(of: "^[A-Z2-9]{10}$", options: .regularExpression) == nil {
            message = "Enter the 10-character join code."; onChange?(); return
        }
        service = url; busy = true; message = "Connecting…"; onChange?()
        generation += 1; let expected = generation
        var req = URLRequest(url: url.appendingPathComponent(cleanCode.map { "\($0)/join" } ?? "parties"))
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Payload: Encodable { let profile: ChimpProfile; let settings: PomodoroSettings }
        req.httpBody = try? JSONEncoder().encode(Payload(profile: profile, settings: settings))
        request = session.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                self.busy = false; self.request = nil
                guard error == nil, let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, data.count < 65536, let member = try? JSONDecoder().decode(PartyMembership.self, from: data) else {
                    let detail = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String:String] }?["error"]
                    self.message = detail ?? "Could not connect. Check the service address and your connection."; self.onChange?(); return
                }
                self.membership = member
                let saved = PartyCredentials.save(member,endpoint:url.absoluteString)
                if !saved { NSLog("Chimpodoro could not save party membership to Keychain; this session will not restore after quitting.") }
                self.onJoined?(); self.connect()
            }
        }
        request?.resume()
    }
    private func connect() {
        guard let membership, let service else { return }
        reconnect?.cancel(); heartbeat?.invalidate()
        var parts = URLComponents(url: service.appendingPathComponent("\(membership.code)/connect"), resolvingAgainstBaseURL: false)!
        parts.scheme = "wss"
        var req = URLRequest(url: parts.url!)
        req.setValue("Bearer \(membership.token)", forHTTPHeaderField: "Authorization")
        socket?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: req); task.maximumMessageSize = 65536
        socket = task; task.resume(); receive(task)
        heartbeat = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self, weak task] _ in
            guard let self, let task else { return }
            task.sendPing { [weak self, weak task] error in
                if error != nil { DispatchQueue.main.async { [weak self, weak task] in
                    if let task { self?.failed(task) }
                } }
            }
            self.send(["type":"sync"])
        }
        message = "Synchronizing…"; onChange?()
    }
    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self, let task, self.socket === task else { return }
                switch result {
                case .failure: self.failed(task)
                case .success(let value):
                    let data: Data
                    switch value { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: self.failed(task); return }
                    guard data.count <= 65536, let object = try? JSONSerialization.jsonObject(with: data) as? [String:Any] else { self.failed(task); return }
                    if object["type"] as? String == "ended" { self.leave(send: false); self.message = "The host ended the party."; self.onChange?(); return }
                    if object["type"] as? String == "error" { self.serverError = object["message"] as? String ?? "Party action failed."; self.message = self.serverError!; self.onChange?() }
                    if let state = try? JSONDecoder().decode(PartyState.self, from: data), state.members.count <= 8, state.duration.isFinite, (60...10800).contains(state.duration), state.remaining.isFinite, (0...state.duration).contains(state.remaining), state.deadline?.isFinite != false, state.serverTime.isFinite {
                        if state.revision >= (self.state?.revision ?? 0) {
                            self.state = state; self.clockDate = Date(timeIntervalSince1970: state.serverTime); self.clockUptime = ProcessInfo.processInfo.systemUptime
                            self.connected = true; self.retry = 0
                            self.message = self.serverError ?? (self.isHost ? "You control the party timer." : "The host controls the party timer.")
                            if self.receivedInitial, let completion = state.completion, completion.id != self.lastCompletion { self.lastCompletion = completion.id; self.onCompletion?(completion) }
                            self.lastCompletion = state.completion?.id; self.receivedInitial = true; self.onChange?()
                        }
                    }
                    self.receive(task)
                }
            }
        }
    }
    private func failed(_ task: URLSessionWebSocketTask) {
        guard socket === task else { return }
        if let response = task.response as? HTTPURLResponse, [403,404].contains(response.statusCode) {
            leave(send:false); message = "Party expired or membership is no longer valid."; onChange?(); return
        }
        connected = false; socket = nil; heartbeat?.invalidate(); task.cancel(with: .goingAway, reason: nil)
        retry += 1
        if retry > 6 { message = "Disconnected. Use Reconnect or leave the party."; onChange?(); return }
        message = "Connection lost. Reconnecting…"; onChange?()
        let work = DispatchWorkItem { [weak self] in self?.connect() }; reconnect = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(30, pow(2, Double(retry))), execute: work)
    }
    func reconnectNow() { guard joined else { return }; retry = 0; connect() }
    private func send(_ object: [String:Any]) {
        guard let task = socket, let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self, weak task] error in
            if error != nil { DispatchQueue.main.async { if let task { self?.failed(task) } } }
        }
    }
    func action(_ action: String, phase: PomodoroPhase? = nil) {
        guard canControl, let state else { return }
        serverError = nil
        var payload: [String:Any] = ["type":"command","action":action,"revision":state.revision]
        if let phase { payload["phase"] = phase.rawValue }
        send(payload)
    }
    func updateProfile() { serverError = nil; if connected { send(["type":"profile","profile":["name":profile.name,"color":profile.color,"accessory":profile.accessory]]) }; onChange?() }
    func leave(send shouldSend: Bool = true) {
        if shouldSend { send(["type":"leave"]) }
        generation += 1; request?.cancel(); request = nil
        reconnect?.cancel(); reconnect = nil; heartbeat?.invalidate(); heartbeat = nil
        let oldSocket = socket; socket = nil
        // Give the explicit leave message time to flush; no retained party timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { oldSocket?.cancel(with: .normalClosure, reason: nil) }
        PartyCredentials.clear()
        serverError = nil
        membership = nil; state = nil; connected = false; busy = false; receivedInitial = false; lastCompletion = nil
        message = "Not in a party."; onLeft?(); onChange?()
    }
}
