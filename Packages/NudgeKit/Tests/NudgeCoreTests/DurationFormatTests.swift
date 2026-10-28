@testable import NudgeCore
import Testing

@Suite struct DurationFormatTests {
    @Test func compact() {
        #expect(DurationFormat.compact(15_120) == "4h 12m")
        #expect(DurationFormat.compact(183_600) == "2d 3h")
        #expect(DurationFormat.compact(30) == "<1m")
    }

    @Test func clock() {
        #expect(DurationFormat.clock(15_127) == "4:12:07")
    }
}
