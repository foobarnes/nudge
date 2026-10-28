import Foundation
@testable import NudgeCore
import Testing

@Suite struct WorkingHoursTests {
    let weekdays = WorkHoursConfig()

    @Test func skipsWeekend() {
        #expect(WorkTime.elapsed(from: at("2026-01-09 17:00"), to: at("2026-01-12 10:00"), config: weekdays,
                                 calendar: newYork) == 7_200)
    }

    @Test func skipsWeekendAcrossSpringForward() {
        #expect(WorkTime.elapsed(from: at("2026-03-06 17:00"), to: at("2026-03-09 10:00"), config: weekdays,
                                 calendar: newYork) == 7_200)
    }

    @Test func zeroWorkingDaysNeverEscalates() {
        let none = WorkHoursConfig(weekdays: [])
        let start = at("2026-01-05 09:00")
        let work = WorkTime.elapsed(from: start, to: start.addingTimeInterval(30 * 86_400), config: none, calendar: newYork)
        #expect(work == 0)
        #expect(TierPolicy.tier(workSeconds: work, TierThresholds()) == .fresh)
        #expect(WorkTime.nextStart(after: start, config: none, calendar: newYork) == nil)
    }

    @Test func dstWindowLengths() {
        let sundayNight = WorkHoursConfig(weekdays: [1], startMinute: 60, endMinute: 240)
        #expect(WorkTime.elapsed(from: at("2026-03-08 00:00"), to: at("2026-03-08 06:00"), config: sundayNight,
                                 calendar: newYork) == 7_200)
        #expect(WorkTime.elapsed(from: at("2026-11-01 00:00"), to: at("2026-11-01 06:00"), config: sundayNight,
                                 calendar: newYork) == 14_400)
    }

    @Test func boundaryInSkippedHourMovesToNextValidTime() {
        let config = WorkHoursConfig(weekdays: [1], startMinute: 150, endMinute: 240) // 02:30 doesn't exist
        let segments = WorkTime.segments(from: at("2026-03-08 00:00"), to: at("2026-03-08 06:00"), config: config,
                                         calendar: newYork)
        #expect(segments.map(\.duration) == [3_600])
    }

    @Test func clampsFutureStart() {
        #expect(WorkTime.elapsed(from: at("2026-01-06 12:00"), to: at("2026-01-06 10:00"), config: weekdays,
                                 calendar: newYork) == 0)
    }

    @Test func segmentsClipToRange() {
        let segments = WorkTime.segments(from: at("2026-01-09 17:00"), to: at("2026-01-12 10:00"), config: weekdays,
                                         calendar: newYork)
        #expect(segments == [DateInterval(start: at("2026-01-09 17:00"), end: at("2026-01-09 18:00")),
                             DateInterval(start: at("2026-01-12 09:00"), end: at("2026-01-12 10:00"))])
    }

    @Test func isWorkingAndNextStart() {
        #expect(WorkTime.isWorking(at: at("2026-01-09 17:59"), config: weekdays, calendar: newYork))
        #expect(!WorkTime.isWorking(at: at("2026-01-09 18:00"), config: weekdays, calendar: newYork))
        #expect(!WorkTime.isWorking(at: at("2026-01-10 12:00"), config: weekdays, calendar: newYork))
        #expect(WorkTime.nextStart(after: at("2026-01-09 17:00"), config: weekdays, calendar: newYork) == at("2026-01-12 09:00"))
        #expect(WorkTime.nextStart(after: at("2026-01-12 08:00"), config: weekdays, calendar: newYork) == at("2026-01-12 09:00"))
        #expect(WorkTime.nextStart(after: at("2026-01-12 09:00"), config: weekdays, calendar: newYork) == at("2026-01-13 09:00"))
    }

    @Test func tiers() {
        let t = TierThresholds()
        #expect(TierPolicy.tier(workSeconds: 3 * 3600, t) == .fresh)
        #expect(TierPolicy.tier(workSeconds: 4 * 3600, t) == .amber)
        #expect(TierPolicy.tier(workSeconds: 8 * 3600, t) == .red)
        #expect(TierPolicy.secondsToNextTier(workSeconds: 3 * 3600, t) == 3600)
        #expect(TierPolicy.secondsToNextTier(workSeconds: 5 * 3600, t) == 10_800)
        #expect(TierPolicy.secondsToNextTier(workSeconds: 9 * 3600, t) == nil)
    }
}

@Suite struct RuleResolverTests {
    @Test func repoOverridesOrg() {
        #expect(RuleResolver.level(repo: "acme/api", orgRules: ["acme": .hidden], repoRules: ["acme/api": .notify]) == .notify)
    }

    @Test func orgRuleApplies() {
        #expect(RuleResolver.level(repo: "acme/api", orgRules: ["acme": .silent], repoRules: [:]) == .silent)
    }

    @Test func unknownOrgNotifies() {
        #expect(RuleResolver.level(repo: "octocat/dotfiles", orgRules: ["acme": .hidden], repoRules: [:]) == .notify)
    }

    @Test func ignoresCase() {
        #expect(RuleResolver.level(repo: "Acme/API", orgRules: [:], repoRules: ["acme/api": .silent]) == .silent)
    }
}
