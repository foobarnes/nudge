@testable import NudgeUI
import Testing

@Suite struct SymbolCatalogTests {
    @Test func everyNameRenders() {
        let missing = SymbolCatalog.entries.map(\.name).filter { !SymbolCatalog.isValid($0) }
        #expect(missing.isEmpty, "Not SF Symbols on this macOS: \(missing)")
    }

    @Test func namesAreUnique() {
        let names = SymbolCatalog.entries.map(\.name)
        #expect(Set(names).count == names.count)
    }

    @Test func emptyQueryListsEverything() {
        #expect(SymbolCatalog.search("  ").count == SymbolCatalog.entries.count)
    }

    @Test func keywordsFindSymbols() {
        #expect(SymbolCatalog.search("git").contains("arrow.triangle.branch"))
        #expect(SymbolCatalog.search("review").contains("eye"))
        #expect(SymbolCatalog.search("bug").contains("ladybug"))
    }

    @Test func exactNameRanksFirst() {
        #expect(SymbolCatalog.search("eye").first == "eye")
        #expect(SymbolCatalog.search("terminal").first == "terminal")
    }

    @Test func everyWordMustMatch() {
        #expect(SymbolCatalog.search("git merge").first == "arrow.triangle.merge")
        #expect(SymbolCatalog.search("zzz nothing").isEmpty)
    }

    @Test func validUncuratedNameIsOffered() {
        #expect(SymbolCatalog.search("tortoise.fill").first == "tortoise.fill")
        #expect(SymbolCatalog.search("not.a.symbol").isEmpty)
    }
}
