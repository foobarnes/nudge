import NudgeCore
@testable import NudgeUI
import Testing

@Suite struct TitlePartsTests {
    @Test func colonKeyIsSplit() {
        let parts = PRRow.titleParts("RLM-4892: Keep filters")
        #expect(parts.key == "RLM-4892")
        #expect(parts.rest == "Keep filters")
    }

    @Test func bracketKeyIsSplit() {
        let parts = PRRow.titleParts("[PROJ-12] Fix login")
        #expect(parts.key == "PROJ-12")
        #expect(parts.rest == "Fix login")
    }

    @Test(arguments: [
        "Fix login",                     // no key
        "UTF-8 decoding for webhooks",   // looks like a key, no separator
        "RLM-4892 Keep filters",         // key without a colon
        "Keep filters (RLM-4892)",       // key at the end
        "feat(api): retries",            // conventional commit
        "rlm-4892: lowercase",           // not a tracker key
        "RLM-4892: ",                    // nothing after the key
    ])
    func otherTitlesStayWhole(title: String) {
        let parts = PRRow.titleParts(title)
        #expect(parts.key == nil)
        #expect(parts.rest == title)
    }
}
