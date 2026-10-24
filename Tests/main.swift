import Foundation

var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String,
            file: StaticString = #file, line: UInt = #line) {
    assertions += 1
    if !condition() {
        fputs("FAIL: \(description) (\(file):\(line))\n", stderr)
        exit(1)
    }
}

func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}
func restored(_ timer: Pomodoro) throws -> Pomodoro {
    try JSONDecoder().decode(Pomodoro.self, from: JSONEncoder().encode(timer))
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let origin = date("2026-10-23T16:00:00Z")

do {
    var timer = Pomodoro()
    expect(timer.settings.focusMinutes == 25, "default focus duration")
    expect(timer.settings.shortBreakMinutes == 5, "default short break")
    expect(timer.settings.longBreakMinutes == 15, "default long break")
    expect(timer.settings.longBreakInterval == 4, "default cycle")
    expect(!timer.settings.autoStartFocus && !timer.settings.autoStartBreaks, "autostart is opt-in")
    expect(timer.phase == .focus && !timer.hasStarted && !timer.isRunning && !timer.isPaused, "initial ready state")
    expect(timer.remaining(at: origin) == 1_500 && timer.progress(at: origin) == 0, "initial time and progress")
    expect(timer.tick(at: origin.addingTimeInterval(1_000_000)) == nil, "idle does not complete")

    timer.start(at: origin)
    expect(timer.isRunning && timer.hasStarted && !timer.isPaused, "start sets running state")
    expect(timer.deadline == origin.addingTimeInterval(1_500), "deadline is wall-clock date")
    timer.start(at: origin.addingTimeInterval(20))
    expect(timer.deadline == origin.addingTimeInterval(1_500), "duplicate start does not extend session")
    expect(timer.remaining(at: origin.addingTimeInterval(750)) == 750, "remaining follows deadline")
    expect(timer.progress(at: origin.addingTimeInterval(750)) == 0.5, "halfway progress")
    expect(timer.tick(at: origin.addingTimeInterval(1_499.999)) == nil, "no early completion")
    let completion = timer.tick(at: origin.addingTimeInterval(1_500), calendar: calendar)
    expect(completion?.phase == .focus && completion?.nextPhase == .shortBreak, "exact deadline completes and changes phase")
    expect(completion?.completedAt == origin.addingTimeInterval(1_500), "completion retains true deadline")
    expect(!timer.hasStarted && timer.deadline == nil && timer.remaining(at: origin) == 300, "next phase waits by default")
    expect(timer.todayStats(at: origin, calendar: calendar).completedFocuses == 1, "one completed focus")
    expect(timer.todayStats(at: origin, calendar: calendar).focusedMinutes == 25, "completed minutes credited")
    expect(timer.tick(at: origin.addingTimeInterval(99_999), calendar: calendar) == nil, "completion cannot credit twice")
    let copy = try restored(timer)
    expect(copy == timer, "completed state roundtrips")
}

do {
    var timer = Pomodoro()
    timer.start(at: origin)
    timer.pause(at: origin.addingTimeInterval(70.25))
    expect(timer.isPaused && timer.deadline == nil, "pause stops deadline")
    expect(timer.remaining(at: origin.addingTimeInterval(99_999)) == 1_429.75, "pause freezes fractional remaining time")
    timer.pause(at: origin.addingTimeInterval(80))
    expect(timer.remaining(at: origin) == 1_429.75, "duplicate pause is harmless")
    timer = try restored(timer)
    expect(timer.isPaused && timer.remaining(at: origin) == 1_429.75, "paused session survives restore")
    let resume = origin.addingTimeInterval(20_000)
    timer.start(at: resume)
    expect(timer.deadline == resume.addingTimeInterval(1_429.75), "resume uses saved remainder")
    expect(timer.tick(at: resume.addingTimeInterval(1_429.74)) == nil, "resumed session not early")
    expect(timer.tick(at: resume.addingTimeInterval(1_429.75), calendar: calendar) != nil, "resumed session completes")
    expect(timer.todayStats(at: resume, calendar: calendar).focusedMinutes == 25, "pause does not change credited duration")
}

do {
    var timer = Pomodoro()
    timer.start(at: origin)
    timer = try restored(timer)
    let wake = origin.addingTimeInterval(8 * 3_600)
    let completion = timer.tick(at: wake, calendar: calendar)
    expect(completion?.completedAt == origin.addingTimeInterval(1_500), "wake uses original completion time")
    expect(timer.phase == .shortBreak && !timer.isRunning, "sleep advances exactly once")
    expect(timer.todayStats(at: origin, calendar: calendar).completedFocuses == 1, "sleep cannot fabricate focus sessions")

    timer.select(.focus, at: wake)
    timer.start(at: wake)
    timer.reset(at: wake.addingTimeInterval(50))
    expect(timer.phase == .focus && timer.remaining(at: wake) == 1_500 && !timer.hasStarted, "reset returns current phase to ready")
    expect(timer.todayStats(at: origin, calendar: calendar).completedFocuses == 1, "reset gives no credit")
    timer.start(at: wake)
    timer.skip(at: wake.addingTimeInterval(50))
    expect(timer.phase == .shortBreak && !timer.hasStarted, "skip moves to ready break")
    expect(timer.completedFocusesInCycle == 1, "skipped focus does not advance completed cycle")
    expect(timer.todayStats(at: origin, calendar: calendar).completedFocuses == 1, "skipped focus gives no credit")
    timer.skip(at: wake.addingTimeInterval(60))
    expect(timer.phase == .focus && !timer.hasStarted, "skip break returns to ready focus")
    timer.select(.longBreak, at: wake)
    expect(timer.remaining(at: wake) == 900 && timer.phase == .longBreak, "manual long break duration")
    timer.select(.focus, at: wake)
    expect(timer.completedFocusesInCycle == 0, "leaving long break begins a new cycle")
}

do {
    var timer = Pomodoro()
    var now = origin
    for round in 1...4 {
        timer.start(at: now)
        expect(timer.nextPhase == (round == 4 ? .longBreak : .shortBreak), "next phase predicts cycle boundary")
        now = now.addingTimeInterval(1_500)
        timer.tick(at: now, calendar: calendar)
        expect(timer.completedFocusesInCycle == round, "completed focus advances cycle once")
        expect(timer.phase == (round == 4 ? .longBreak : .shortBreak), "long break only after fourth completed focus")
        if round < 4 { timer.skip(at: now) }
    }
    expect(timer.todayStats(at: now, calendar: calendar).focusedMinutes == 100, "four complete sessions total 100 minutes")
    timer.start(at: now)
    timer.tick(at: now.addingTimeInterval(900), calendar: calendar)
    expect(timer.phase == .focus && timer.completedFocusesInCycle == 0, "finishing long break resets cycle")
    expect(timer.todayStats(at: now, calendar: calendar).completedFocuses == 4, "break never contributes focus stats")
}

do {
    let settings = PomodoroSettings(focusMinutes: 1, shortBreakMinutes: 1,
        longBreakMinutes: 2, longBreakInterval: 1, autoStartBreaks: true, autoStartFocus: true)
    var timer = Pomodoro(settings: settings)
    timer.start(at: origin)
    let wake = origin.addingTimeInterval(10 * 3_600)
    timer.tick(at: wake, calendar: calendar)
    expect(timer.phase == .longBreak && timer.isRunning, "autostart break after completion")
    expect(timer.deadline == wake.addingTimeInterval(120), "autostart begins on observed wake time")
    expect(timer.tick(at: wake, calendar: calendar) == nil, "no cascade when both autostarts enabled")
    expect(timer.todayStats(at: origin, calendar: calendar).completedFocuses == 1, "autostart sleep does not invent work")
    timer.tick(at: wake.addingTimeInterval(120), calendar: calendar)
    expect(timer.phase == .focus && timer.isRunning && timer.completedFocusesInCycle == 0, "autostart focus after long break")
    expect(timer.deadline == wake.addingTimeInterval(180), "next focus has full duration")

    let overduePause = timer.pause(at: wake.addingTimeInterval(200), calendar: calendar)
    expect(overduePause?.phase == .focus, "pause reconciles an overdue focus")
    expect(timer.phase == .longBreak && !timer.hasStarted && !timer.isRunning, "overdue pause leaves successor ready")

    timer.select(.focus, at: wake.addingTimeInterval(200))
    timer.start(at: wake.addingTimeInterval(200))
    let skipped = timer.skip(at: wake.addingTimeInterval(300), calendar: calendar)
    expect(skipped?.phase == .focus && timer.phase == .longBreak, "overdue skip advances only once")
}

do {
    var timer = Pomodoro(settings: PomodoroSettings(focusMinutes: 1))
    // Deadline is Oct 23 at 23:59 PDT, observed after midnight on Oct 24.
    let start = date("2026-10-24T06:58:00Z")
    let wake = date("2026-10-24T07:30:00Z")
    timer.start(at: start)
    timer.tick(at: wake, calendar: calendar)
    expect(timer.todayStats(at: start, calendar: calendar).completedFocuses == 1, "overnight wake credits actual completion day")
    expect(timer.todayStats(at: wake, calendar: calendar).completedFocuses == 0, "overnight wake does not move yesterday's work to today")
    expect(timer.history.first?.dayKey == "2026-10-23", "history uses supplied local calendar")

    timer.select(.focus, at: wake)
    let beforeMidnight = date("2026-10-25T06:59:30Z")
    timer.start(at: beforeMidnight)
    timer.tick(at: beforeMidnight.addingTimeInterval(60), calendar: calendar)
    expect(timer.history.last?.dayKey == "2026-10-25", "session crossing midnight belongs to day it completes")
}

do {
    var timer = Pomodoro()
    timer.start(at: origin)
    timer.updateSettings(PomodoroSettings(focusMinutes: 42, shortBreakMinutes: 8), at: origin.addingTimeInterval(10))
    expect(timer.sessionDuration == 1_500 && timer.deadline == origin.addingTimeInterval(1_500), "settings preserve in-flight focus")
    timer.pause(at: origin.addingTimeInterval(20))
    timer.updateSettings(PomodoroSettings(focusMinutes: 35, shortBreakMinutes: 8), at: origin.addingTimeInterval(30))
    expect(timer.sessionDuration == 1_500 && timer.remaining(at: origin) == 1_480, "settings preserve paused focus")
    timer.start(at: origin.addingTimeInterval(40))
    timer.tick(at: origin.addingTimeInterval(1_520), calendar: calendar)
    expect(timer.todayStats(at: origin, calendar: calendar).focusedMinutes == 25, "settings do not rewrite completed session length")
    expect(timer.remaining(at: origin) == 480, "next phase receives new duration")
    timer.select(.focus, at: origin.addingTimeInterval(1_520))
    expect(timer.sessionDuration == 2_100, "next focus receives new duration")
    timer.updateSettings(PomodoroSettings(focusMinutes: 30), at: origin.addingTimeInterval(1_520))
    expect(timer.sessionDuration == 1_800, "ready phase immediately reflects duration preference")

    var invalidSettings = PomodoroSettings(focusMinutes: -2, shortBreakMinutes: 999,
        longBreakMinutes: 0, longBreakInterval: 0)
    expect(invalidSettings.focusMinutes == 1 && invalidSettings.shortBreakMinutes == 60, "initial duration bounds")
    expect(invalidSettings.longBreakMinutes == 1 && invalidSettings.longBreakInterval == 1, "initial break and cycle bounds")
    invalidSettings.focusMinutes = Int.max
    invalidSettings.longBreakInterval = Int.max
    timer.updateSettings(invalidSettings, at: origin.addingTimeInterval(1_520))
    expect(timer.settings.focusMinutes == 180 && timer.settings.longBreakInterval == 12, "mutated settings are normalized before use")
}

do {
    var timer = Pomodoro(settings: PomodoroSettings(focusMinutes: 1))
    for day in 0..<35 {
        let now = calendar.date(byAdding: .day, value: day, to: origin)!
        timer.select(.focus, at: now)
        timer.start(at: now)
        timer.tick(at: now.addingTimeInterval(60), calendar: calendar)
    }
    expect(timer.history.count == 30, "history bounded to 30 daily entries")
    expect(timer.todayStats(at: origin, calendar: calendar).completedFocuses == 0, "oldest history is pruned")
    expect(timer.history.first?.dayKey == "2026-10-28", "most recent 30 daily entries retained")
    let copy = try restored(timer)
    expect(copy == timer, "bounded history roundtrips")

    let encoded = try JSONEncoder().encode(timer)
    var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    object["sessionDuration"] = 0
    let invalid = try JSONSerialization.data(withJSONObject: object)
    do {
        _ = try JSONDecoder().decode(Pomodoro.self, from: invalid)
        expect(false, "invalid saved duration must fail decoding")
    } catch {
        expect(true, "invalid saved duration rejected")
    }
}

let shared = Pomodoro.partyView(settings: PomodoroSettings(), phase: .shortBreak, duration: 300, remaining: 300, deadline: origin.timeIntervalSince1970 + 240, started: true, cycle: 2)
expect(shared.remaining(at: origin) == 240, "party view uses shared deadline")
expect(shared.phase == .shortBreak && shared.completedFocusesInCycle == 2, "party view preserves phase and cycle")
expect(shared.todayStats(at: origin).completedFocuses == 0, "party view does not invent personal credit")
let sharedPaused = Pomodoro.partyView(settings: PomodoroSettings(), phase: .focus, duration: 1500, remaining: 400, deadline: nil, started: true, cycle: 0)
expect(sharedPaused.isPaused && sharedPaused.remaining(at: origin) == 400, "party pause snapshot is stable")

print("Passed \(assertions) Pomodoro assertions.")
