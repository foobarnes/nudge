import Foundation

/// Working windows are built per calendar day with `.nextTime` / `.first`, so a boundary in a skipped hour moves
/// to the next valid time and a repeated hour uses its first occurrence. Elapsed time inside a window is real seconds.
enum WorkWindows {
    static func window(on day: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> DateInterval? {
        guard config.weekdays.contains(calendar.component(.weekday, from: day)),
              config.endMinute > config.startMinute,
              let start = time(config.startMinute, on: day, calendar),
              let end = time(config.endMinute, on: day, calendar),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func time(_ minute: Int, on day: Date, _ calendar: Calendar) -> Date? {
        let midnight = calendar.startOfDay(for: day)
        if minute >= 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: midnight) }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: midnight,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }

    /// Windows of every day that overlaps [from, to].
    static func windows(from: Date, to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> [DateInterval] {
        guard !config.weekdays.isEmpty, to > from else { return [] }
        var result: [DateInterval] = []
        var day = calendar.startOfDay(for: from)
        while day < to {
            if let w = window(on: day, config, calendar) { result.append(w) }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

func _workTimeSegments(_ from: Date, _ to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> [DateInterval] {
    WorkWindows.windows(from: from, to: to, config, calendar).compactMap { w in
        let start = max(w.start, from), end = min(w.end, to)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
}

func _workTimeElapsed(_ from: Date, _ to: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> TimeInterval {
    _workTimeSegments(from, to, config, calendar).reduce(0) { $0 + $1.duration }
}

func _workTimeIsWorking(_ date: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Bool {
    guard let w = WorkWindows.window(on: date, config, calendar) else { return false }
    return w.start <= date && date < w.end
}

func _workTimeNextStart(_ date: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    guard !config.weekdays.isEmpty else { return nil }
    var day = calendar.startOfDay(for: date)
    for _ in 0..<15 {
        if let w = WorkWindows.window(on: day, config, calendar), w.start > date { return w.start }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        day = next
    }
    return nil
}
