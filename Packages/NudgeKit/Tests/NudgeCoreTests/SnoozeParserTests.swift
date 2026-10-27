import Foundation
@testable import NudgeCore
import Testing

@Suite struct SnoozeParserTests {
    let now = at("2026-01-07 10:00") // Wednesday
    let config = WorkHoursConfig()

    func parse(_ text: String) -> Date? { SnoozeParser.parse(text, now: now, config: config, calendar: newYork) }

    @Test func durations() {
        #expect(parse("45m") == now.addingTimeInterval(2_700))
        #expect(parse("2h") == now.addingTimeInterval(7_200))
        #expect(parse("1h30m") == now.addingTimeInterval(5_400))
        #expect(parse("1h 30m") == now.addingTimeInterval(5_400))
        #expect(parse("90") == now.addingTimeInterval(5_400))
        #expect(parse(" 2H ") == now.addingTimeInterval(7_200))
    }

    @Test func clockTimes() {
        #expect(parse("4pm") == at("2026-01-07 16:00"))
        #expect(parse("4:30PM") == at("2026-01-07 16:30"))
        #expect(parse("16:30") == at("2026-01-07 16:30"))
        #expect(parse("12pm") == at("2026-01-07 12:00"))
    }

    @Test func days() {
        #expect(parse("tomorrow") == at("2026-01-08 09:00"))
        #expect(parse("Mon") == at("2026-01-12 09:00"))
        #expect(parse("fri") == at("2026-01-09 09:00"))
        #expect(parse("wed") == at("2026-01-14 09:00"))
    }

    @Test func rejectsGarbageAndPast() {
        for text in ["", "soon", "0", "h", "1x", "25:00", "13pm", "9am", "08:00", "4:5pm", "m"] {
            #expect(parse(text) == nil, "\(text)")
        }
    }

    @Test func resolvesOptions() {
        func resolve(_ option: SnoozeOption, _ now: Date) -> Date? {
            SnoozeParser.resolve(option, now: now, config: config, calendar: newYork)
        }
        #expect(resolve(.minutes(15), now) == now.addingTimeInterval(900))
        #expect(resolve(.untilTomorrow, at("2026-01-09 10:00")) == at("2026-01-10 09:00"))
        #expect(resolve(.untilNextWorkDay, at("2026-01-09 18:30")) == at("2026-01-12 09:00"))
        #expect(resolve(.until(at("2026-01-07 15:00")), now) == at("2026-01-07 15:00"))
        #expect(resolve(.until(at("2026-01-07 09:00")), now) == nil)
        #expect(SnoozeParser.resolve(.untilNextWorkDay, now: now, config: WorkHoursConfig(weekdays: []),
                                     calendar: newYork) == nil)
    }
}
