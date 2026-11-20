import Testing
@testable import StickyCore

@Suite("List formatting")
struct ListFormattingTests {
    @Test func dashOrOneAtLineStartBecomeMarkers() {
        #expect(ListFormatting.replacementOnSpace(linePrefix: "-") == "• ")
        #expect(ListFormatting.replacementOnSpace(linePrefix: "*") == "• ")
        #expect(ListFormatting.replacementOnSpace(linePrefix: "1") == "1. ")
        #expect(ListFormatting.replacementOnSpace(linePrefix: "  -") == "  • ")
    }

    @Test func otherPrefixesAreLeftAlone() {
        #expect(ListFormatting.replacementOnSpace(linePrefix: "") == nil)
        #expect(ListFormatting.replacementOnSpace(linePrefix: "a -") == nil)
        #expect(ListFormatting.replacementOnSpace(linePrefix: "30") == nil)
        #expect(ListFormatting.replacementOnSpace(linePrefix: "--") == nil)
        #expect(ListFormatting.replacementOnSpace(linePrefix: "• comprar") == nil)
    }

    @Test func returnContinuesLists() {
        #expect(ListFormatting.newlineAction(line: "• leche") == .insert("\n• "))
        #expect(ListFormatting.newlineAction(line: "- leche") == .insert("\n• "))
        #expect(ListFormatting.newlineAction(line: "1. uno") == .insert("\n2. "))
        #expect(ListFormatting.newlineAction(line: "9. nueve") == .insert("\n10. "))
        #expect(ListFormatting.newlineAction(line: "  • sub") == .insert("\n  • "))
    }

    @Test func returnOnEmptyItemEndsList() {
        #expect(ListFormatting.newlineAction(line: "• ") == .endList(markerLength: 2))
        #expect(ListFormatting.newlineAction(line: "12. ") == .endList(markerLength: 4))
        #expect(ListFormatting.newlineAction(line: "  • ") == .endList(markerLength: 4))
    }

    @Test func plainLinesGetPlainNewline() {
        #expect(ListFormatting.newlineAction(line: "Revisar 30 min") == .plain)
        #expect(ListFormatting.newlineAction(line: "1.5 kg") == .plain)
        #expect(ListFormatting.newlineAction(line: "") == .plain)
    }

    @Test func trailingEmptyItemsAreDropped() {
        #expect(ListFormatting.trimmingEmptyTrailingItems("Súper\n• leche\n• ") == "Súper\n• leche")
        #expect(ListFormatting.trimmingEmptyTrailingItems("1. a\n2. \n") == "1. a")
        #expect(ListFormatting.trimmingEmptyTrailingItems("• ") == "")
        #expect(ListFormatting.trimmingEmptyTrailingItems("sin lista") == "sin lista")
    }
}
