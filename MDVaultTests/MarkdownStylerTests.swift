import Foundation
import Testing
@testable import MDVault

struct MarkdownStylerTests {
    private func ranges(_ source: String, _ style: MarkdownStyler.Style) -> [Range<Int>] {
        MarkdownStyler.runs(for: source)
            .filter { $0.style == style }
            .map(\.utf8Range)
            .sorted { $0.lowerBound < $1.lowerBound }
    }

    // MARK: Per-node runs and markers

    @Test(arguments: 1...6)
    func headingLevelAndMarker(level: Int) {
        let source = String(repeating: "#", count: level) + " Title"
        #expect(ranges(source, .heading(level: level)) == [0..<source.utf8.count])
        #expect(ranges(source, .syntaxMarker) == [0..<(level + 1)])
    }

    @Test func strongWithDelimiterMarkers() {
        let source = "a **bold** z"
        #expect(ranges(source, .strong) == [2..<10])
        #expect(ranges(source, .syntaxMarker) == [2..<4, 8..<10])
    }

    @Test func emphasisWithDelimiterMarkers() {
        let source = "a *it* z"
        #expect(ranges(source, .emphasis) == [2..<6])
        #expect(ranges(source, .syntaxMarker) == [2..<3, 5..<6])
    }

    @Test func nestedEmphasisInsideStrong() {
        let source = "**bold *it* end**"
        #expect(ranges(source, .strong) == [0..<17])
        #expect(ranges(source, .emphasis) == [7..<11])
        #expect(ranges(source, .syntaxMarker) == [0..<2, 7..<8, 10..<11, 15..<17])
    }

    @Test func strikethroughWithDelimiterMarkers() {
        let source = "a ~~gone~~ z"
        #expect(ranges(source, .strikethrough) == [2..<10])
        #expect(ranges(source, .syntaxMarker) == [2..<4, 8..<10])
    }

    @Test func inlineCodeBacktickMarkers() {
        let source = "x `code` y"
        #expect(ranges(source, .inlineCode) == [2..<8])
        #expect(ranges(source, .syntaxMarker) == [2..<3, 7..<8])
    }

    @Test func linkTextVersusDestinationMarkers() {
        let source = "[text](https://a.co)"
        #expect(ranges(source, .link) == [0..<20])
        #expect(ranges(source, .syntaxMarker) == [0..<1, 5..<20])
    }

    @Test func blockQuoteDimsLeadingAnglePerLine() {
        let source = "> a\n> b"
        #expect(ranges(source, .blockQuote) == [0..<7])
        #expect(ranges(source, .syntaxMarker) == [0..<2, 4..<6])
    }

    @Test func fencedCodeBlock() {
        let source = "```\nlet x = 1\n```"
        #expect(ranges(source, .codeBlock) == [0..<source.utf8.count])
    }

    @Test func unorderedListItemMarkers() {
        let source = "- one\n- two"
        #expect(ranges(source, .listMarker) == [0..<2, 6..<8])
    }

    @Test func orderedListItemMarkers() {
        let source = "1. one\n2. two"
        #expect(ranges(source, .listMarker) == [0..<3, 7..<10])
    }

    @Test func thematicBreakRun() {
        let source = "---"
        #expect(ranges(source, .thematicBreak) == [0..<3])
    }

    // MARK: Offset semantics

    @Test func multibytePrefixPinsUTF8Columns() {
        // "héllo 🎉 " is 12 UTF-8 bytes; if swift-markdown columns were
        // character- or scalar-oriented these ranges would be wrong.
        let source = "héllo 🎉 **bold**"
        #expect(ranges(source, .strong) == [12..<20])
        #expect(ranges(source, .syntaxMarker) == [12..<14, 18..<20])
    }

    // MARK: Edge cases

    @Test func emptySourceProducesNoRuns() {
        #expect(MarkdownStyler.runs(for: "").isEmpty)
    }

    @Test func bareDelimitersStayInBounds() {
        let source = "**"
        for run in MarkdownStyler.runs(for: source) {
            #expect(run.utf8Range.lowerBound >= 0)
            #expect(run.utf8Range.upperBound <= source.utf8.count)
        }
    }

    @Test func unterminatedFenceStaysInBounds() {
        let source = "```\nlet x = 1"
        let all = MarkdownStyler.runs(for: source)
        #expect(all.contains { $0.style == .codeBlock })
        for run in all {
            #expect(run.utf8Range.lowerBound >= 0)
            #expect(run.utf8Range.upperBound <= source.utf8.count)
        }
    }

    @Test func kitchenSinkStaysInBounds() {
        let source = """
        # Title 🎉 with **bold**

        Paragraph with *emphasis*, `code`, and [a link](https://example.com).

        > A quote
        > spanning lines

        ```swift
        let code = "fenced"
        ```

        - item one
        - item **two**

        ---
        """
        let all = MarkdownStyler.runs(for: source)
        #expect(!all.isEmpty)
        let count = source.utf8.count
        for run in all {
            #expect(run.utf8Range.lowerBound >= 0)
            #expect(run.utf8Range.upperBound <= count)
            #expect(run.utf8Range.lowerBound <= run.utf8Range.upperBound)
        }
    }

    // MARK: Application invariants

    @Test func styledTextPreservesCharacters() {
        let source = "# Hi\n**bold** and `code` plus 🎉"
        let styled = MarkdownStyler.styledText(source, fontSize: 14)
        #expect(String(styled.characters) == source)
    }
}
