import Foundation

private let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]

func _snoozeParse(_ text: String, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !s.isEmpty else { return nil }
    let end: Date?
    if s == "tomorrow" {
        end = tomorrowStart(now, config, calendar)
    } else if s.count >= 3, let index = weekdayNames.firstIndex(where: { $0.hasPrefix(s) }) {
        end = weekdayStart(index + 1, now, config, calendar)
    } else if let seconds = durationSeconds(s) {
        end = now.addingTimeInterval(seconds)
    } else if let minute = clockMinute(s) {
        end = WorkWindows.time(minute, on: now, calendar)
    } else {
        end = nil
    }
    return end.flatMap { $0 > now ? $0 : nil }
}

func _snoozeResolve(_ option: SnoozeOption, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    let end: Date? = switch option {
    case let .minutes(m): now.addingTimeInterval(TimeInterval(m * 60))
    case let .until(date): date
    case .untilTomorrow: tomorrowStart(now, config, calendar)
    case .untilNextWorkDay: WorkTime.nextStart(after: now, config: config, calendar: calendar)
    }
    return end.flatMap { $0 > now ? $0 : nil }
}

private func tomorrowStart(_ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        .flatMap { WorkWindows.time(config.startMinute, on: $0, calendar) }
}

/// The next date on `weekday` (1 = Sunday) whose work start is after `now`.
private func weekdayStart(_ weekday: Int, _ now: Date, _ config: WorkHoursConfig, _ calendar: Calendar) -> Date? {
    var day = calendar.startOfDay(for: now)
    for _ in 0..<8 {
        if calendar.component(.weekday, from: day) == weekday,
           let start = WorkWindows.time(config.startMinute, on: day, calendar), start > now { return start }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
        day = next
    }
    return nil
}

/// "45m", "2h", "1h30m", "1h 30m", "90" (bare number = minutes).
private func durationSeconds(_ s: String) -> TimeInterval? {
    if let minutes = Int(s) { return minutes > 0 ? TimeInterval(minutes * 60) : nil }
    var total = 0, number = "", sawUnit = false
    for ch in s where ch != " " {
        if ch.isASCII, ch.isNumber {
            number.append(ch)
        } else if ch == "h" || ch == "m", let n = Int(number) {
            total += ch == "h" ? n * 3600 : n * 60
            number = ""; sawUnit = true
        } else {
            return nil
        }
    }
    return sawUnit && number.isEmpty && total > 0 ? TimeInterval(total) : nil
}

/// "4pm", "4:30pm", "4 pm", "16:30" → minutes after midnight.
private func clockMinute(_ s: String) -> Int? {
    var body = s.replacingOccurrences(of: " ", with: "")
    var meridiem: String?
    for suffix in ["am", "pm"] where body.hasSuffix(suffix) {
        meridiem = suffix; body.removeLast(2)
    }
    let parts = body.split(separator: ":", omittingEmptySubsequences: false)
    guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) }),
          var hour = Int(parts[0]) else { return nil }
    let minute = parts.count == 2 ? Int(parts[1]) : 0
    guard let minute, (0..<60).contains(minute), parts.count == 2 ? parts[1].count == 2 : true else { return nil }
    if let meridiem {
        guard (1...12).contains(hour) else { return nil }
        hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
    } else {
        guard parts.count == 2, (0..<24).contains(hour) else { return nil }
    }
    return hour * 60 + minute
}
