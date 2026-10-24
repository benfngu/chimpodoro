import Foundation

enum PomodoroPhase: String, Codable, CaseIterable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: return "focus"
        case .shortBreak: return "short break"
        case .longBreak: return "long break"
        }
    }
}

struct PomodoroSettings: Codable, Equatable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var longBreakInterval: Int
    var autoStartBreaks: Bool
    var autoStartFocus: Bool

    init(focusMinutes: Int = 25, shortBreakMinutes: Int = 5,
         longBreakMinutes: Int = 15, longBreakInterval: Int = 4,
         autoStartBreaks: Bool = false, autoStartFocus: Bool = false) {
        self.focusMinutes = min(180, max(1, focusMinutes))
        self.shortBreakMinutes = min(60, max(1, shortBreakMinutes))
        self.longBreakMinutes = min(120, max(1, longBreakMinutes))
        self.longBreakInterval = min(12, max(1, longBreakInterval))
        self.autoStartBreaks = autoStartBreaks
        self.autoStartFocus = autoStartFocus
    }

    var normalized: Self {
        Self(focusMinutes: focusMinutes, shortBreakMinutes: shortBreakMinutes,
             longBreakMinutes: longBreakMinutes, longBreakInterval: longBreakInterval,
             autoStartBreaks: autoStartBreaks, autoStartFocus: autoStartFocus)
    }

    func duration(for phase: PomodoroPhase) -> TimeInterval {
        let safe = normalized
        switch phase {
        case .focus: return TimeInterval(safe.focusMinutes * 60)
        case .shortBreak: return TimeInterval(safe.shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(safe.longBreakMinutes * 60)
        }
    }
}

struct PomodoroDay: Codable, Equatable {
    let dayKey: String
    var completedFocuses: Int
    var focusedMinutes: Int
}

struct PomodoroCompletion: Equatable {
    let phase: PomodoroPhase
    let completedAt: Date
    let nextPhase: PomodoroPhase
}

/// A wall-clock timer with no scheduling, disk I/O, or UI dependencies.
/// The owner persists after actions and non-nil tick results, never every second.
struct Pomodoro: Codable, Equatable {
    private(set) var settings: PomodoroSettings
    private(set) var phase: PomodoroPhase = .focus
    private(set) var deadline: Date?
    private(set) var sessionDuration: TimeInterval
    private(set) var completedFocusesInCycle = 0
    private(set) var history: [PomodoroDay] = []
    private(set) var hasStarted = false
    private var pausedRemaining: TimeInterval

    init(settings: PomodoroSettings = PomodoroSettings()) {
        self.settings = settings.normalized
        sessionDuration = self.settings.duration(for: .focus)
        pausedRemaining = sessionDuration
    }

    static func partyView(settings: PomodoroSettings, phase: PomodoroPhase, duration: Double, remaining: Double, deadline: Double?, started: Bool, cycle: Int) -> Pomodoro {
        var timer = Pomodoro(settings: settings)
        timer.phase = phase
        timer.sessionDuration = duration
        timer.pausedRemaining = remaining
        timer.deadline = deadline.map { Date(timeIntervalSince1970: $0) }
        timer.hasStarted = started
        timer.completedFocusesInCycle = min(timer.settings.longBreakInterval, max(0, cycle))
        return timer
    }

    var isRunning: Bool { deadline != nil }
    var isPaused: Bool { hasStarted && deadline == nil }

    var nextPhase: PomodoroPhase {
        switch phase {
        case .focus:
            return completedFocusesInCycle + 1 >= settings.longBreakInterval ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: return .focus
        }
    }

    func remaining(at now: Date = Date()) -> TimeInterval {
        let value = deadline.map { $0.timeIntervalSince(now) } ?? pausedRemaining
        return min(sessionDuration, max(0, value))
    }

    func progress(at now: Date = Date()) -> Double {
        1 - remaining(at: now) / sessionDuration
    }

    func todayStats(at now: Date = Date(), calendar: Calendar = .current) -> PomodoroDay {
        let key = Self.dayKey(for: now, calendar: calendar)
        return history.first { $0.dayKey == key }
            ?? PomodoroDay(dayKey: key, completedFocuses: 0, focusedMinutes: 0)
    }

    @discardableResult
    mutating func start(at now: Date = Date(), calendar: Calendar = .current) -> PomodoroCompletion? {
        let completion = tick(at: now, calendar: calendar)
        guard !isRunning else { return completion }
        deadline = now.addingTimeInterval(pausedRemaining)
        hasStarted = true
        return completion
    }

    @discardableResult
    mutating func pause(at now: Date = Date(), calendar: Calendar = .current) -> PomodoroCompletion? {
        let completion = tick(at: now, calendar: calendar)
        if completion != nil {
            // An overdue pause must not unexpectedly leave a new session running.
            prepare(phase)
        } else if isRunning {
            pausedRemaining = remaining(at: now)
            deadline = nil
        }
        return completion
    }

    @discardableResult
    mutating func reset(at now: Date = Date(), calendar: Calendar = .current) -> PomodoroCompletion? {
        let completion = tick(at: now, calendar: calendar)
        prepare(phase)
        return completion
    }

    @discardableResult
    mutating func skip(at now: Date = Date(), calendar: Calendar = .current) -> PomodoroCompletion? {
        // A completed timer already advanced once; don't skip its successor too.
        if let completion = tick(at: now, calendar: calendar) { return completion }
        if phase == .focus {
            prepare(.shortBreak)
        } else {
            if phase == .longBreak { completedFocusesInCycle = 0 }
            prepare(.focus)
        }
        return nil
    }

    @discardableResult
    mutating func select(_ newPhase: PomodoroPhase, at now: Date = Date(),
                         calendar: Calendar = .current) -> PomodoroCompletion? {
        let completion = tick(at: now, calendar: calendar)
        if phase == .longBreak && newPhase != .longBreak { completedFocusesInCycle = 0 }
        prepare(newPhase)
        return completion
    }

    @discardableResult
    mutating func updateSettings(_ newSettings: PomodoroSettings, at now: Date = Date(),
                                 calendar: Calendar = .current) -> PomodoroCompletion? {
        let completion = tick(at: now, calendar: calendar)
        settings = newSettings.normalized
        completedFocusesInCycle = min(completedFocusesInCycle, settings.longBreakInterval)
        // A running or paused session keeps the duration it began with.
        if !hasStarted { prepare(phase) }
        return completion
    }

    /// Handles at most one completion, even after a long sleep or app absence.
    /// Autostart uses `now` for the next session instead of fabricating missed work.
    @discardableResult
    mutating func tick(at now: Date = Date(), calendar: Calendar = .current) -> PomodoroCompletion? {
        guard let due = deadline, now >= due else { return nil }
        let finishedPhase = phase
        if finishedPhase == .focus {
            completedFocusesInCycle = min(settings.longBreakInterval, completedFocusesInCycle + 1)
            recordFocus(completedAt: due, calendar: calendar)
        } else if finishedPhase == .longBreak {
            completedFocusesInCycle = 0
        }

        let successor: PomodoroPhase = finishedPhase == .focus
            ? (completedFocusesInCycle >= settings.longBreakInterval ? .longBreak : .shortBreak)
            : .focus
        prepare(successor)
        let shouldStart = successor == .focus ? settings.autoStartFocus : settings.autoStartBreaks
        if shouldStart {
            deadline = now.addingTimeInterval(sessionDuration)
            hasStarted = true
        }
        return PomodoroCompletion(phase: finishedPhase, completedAt: due, nextPhase: successor)
    }

    private mutating func prepare(_ newPhase: PomodoroPhase) {
        phase = newPhase
        sessionDuration = settings.duration(for: newPhase)
        pausedRemaining = sessionDuration
        deadline = nil
        hasStarted = false
    }

    private mutating func recordFocus(completedAt date: Date, calendar: Calendar) {
        let key = Self.dayKey(for: date, calendar: calendar)
        let minutes = Int(sessionDuration / 60)
        if let index = history.firstIndex(where: { $0.dayKey == key }) {
            history[index].completedFocuses += 1
            history[index].focusedMinutes += minutes
        } else {
            history.append(PomodoroDay(dayKey: key, completedFocuses: 1, focusedMinutes: minutes))
        }
        history.sort { $0.dayKey < $1.dayKey }
        if history.count > 30 { history.removeFirst(history.count - 30) }
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private enum CodingKeys: String, CodingKey {
        case settings, phase, deadline, sessionDuration, completedFocusesInCycle
        case history, hasStarted, pausedRemaining
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        settings = try values.decode(PomodoroSettings.self, forKey: .settings).normalized
        phase = try values.decode(PomodoroPhase.self, forKey: .phase)
        deadline = try values.decodeIfPresent(Date.self, forKey: .deadline)
        sessionDuration = try values.decode(TimeInterval.self, forKey: .sessionDuration)
        pausedRemaining = try values.decode(TimeInterval.self, forKey: .pausedRemaining)
        hasStarted = try values.decode(Bool.self, forKey: .hasStarted)
        completedFocusesInCycle = min(settings.longBreakInterval,
            max(0, try values.decode(Int.self, forKey: .completedFocusesInCycle)))
        history = try values.decode([PomodoroDay].self, forKey: .history)
        guard sessionDuration.isFinite, (60...10_800).contains(sessionDuration),
              pausedRemaining.isFinite, (0...sessionDuration).contains(pausedRemaining),
              deadline?.timeIntervalSinceReferenceDate.isFinite != false,
              deadline == nil || hasStarted,
              hasStarted || pausedRemaining == sessionDuration else {
            throw DecodingError.dataCorruptedError(forKey: .sessionDuration, in: values,
                debugDescription: "Invalid saved Pomodoro session")
        }
        // A bounded local history keeps preferences small even after years of use.
        history = Array(history.filter { $0.completedFocuses >= 0 && $0.focusedMinutes >= 0 }
            .sorted { $0.dayKey < $1.dayKey }.suffix(30))
    }
}
