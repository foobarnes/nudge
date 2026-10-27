import Foundation

// Placeholder bodies so NudgeUI and the shell compile while NudgeCore is built in parallel.
// The core implementation replaces this file (WorkTime.swift, SnoozeParser.swift).

func _workTimeElapsed(_ from: Date, _ to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> TimeInterval {
    max(0, to.timeIntervalSince(from))
}

func _workTimeSegments(_ from: Date, _ to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> [DateInterval] {
    to > from ? [DateInterval(start: from, end: to)] : []
}

func _workTimeIsWorking(_ date: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Bool { true }

func _workTimeNextStart(_ date: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    date.addingTimeInterval(3600)
}

func _snoozeParse(_ text: String, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? { nil }

func _snoozeResolve(_ option: SnoozeOption, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    switch option {
    case let .minutes(m): now.addingTimeInterval(TimeInterval(m * 60))
    case let .until(date): date
    case .untilTomorrow, .untilNextWorkDay: now.addingTimeInterval(16 * 3600)
    }
}
