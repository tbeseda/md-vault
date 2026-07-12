import Markdown
import SwiftUI

/// Overlays presentation attributes on raw markdown source.
///
/// The styled text's characters are always identical to the source string;
/// only attributes differ. `runs(for:)` is a pure function over the source
/// and the primary unit-test surface.
enum MarkdownStyler {
    struct StyleRun: Equatable, Sendable {
        let utf8Range: Range<Int>
        let style: Style
    }

    enum Style: Equatable, Sendable {
        case heading(level: Int)
        case strong
        case emphasis
        case inlineCode
        case codeBlock
        case link
        case blockQuote
        case listMarker
        case thematicBreak
        case syntaxMarker
    }

    // MARK: - Run generation

    /// Parse the source and emit attribute runs keyed by UTF-8 offset ranges.
    static func runs(for source: String) -> [StyleRun] {
        var walker = RunWalker(source: source)
        walker.visit(Document(parsing: source))
        return walker.runs
    }

    // MARK: - Attribute application

    /// Build a styled AttributedString from scratch. Only for open/reload,
    /// where a selection reset is correct; while editing, use `applyRuns`
    /// so `OpenDocument.restyle` can preserve the selection.
    static func styledText(_ source: String, fontSize: CGFloat) -> AttributedString {
        var text = AttributedString(source)
        applyRuns(runs(for: source), to: &text, fontSize: fontSize)
        return text
    }

    /// Reset the whole string to base attributes, then overlay the runs.
    /// Attribute-only: never inserts or removes characters.
    static func applyRuns(_ runs: [StyleRun], to text: inout AttributedString, fontSize: CGFloat) {
        var base = AttributeContainer()
        base.font = .system(size: fontSize)
        text.setAttributes(base)

        // Wider runs sort before the narrower runs they contain, so children
        // override parents and the ambient-context trackers see parents first.
        let ordered = runs.sorted {
            $0.utf8Range.lowerBound != $1.utf8Range.lowerBound
                ? $0.utf8Range.lowerBound < $1.utf8Range.lowerBound
                : $0.utf8Range.upperBound > $1.utf8Range.upperBound
        }

        let utf8 = text.utf8
        let total = utf8.count
        var cursorOffset = 0
        var cursorIndex = utf8.startIndex
        var activeHeading: (range: Range<Int>, level: Int)?
        var activeStrong: Range<Int>?
        var activeEmphasis: Range<Int>?

        for run in ordered {
            let lower = min(max(run.utf8Range.lowerBound, 0), total)
            let upper = min(max(run.utf8Range.upperBound, lower), total)
            guard lower < upper else { continue }

            switch run.style {
            case .heading(let level): activeHeading = (lower..<upper, level)
            case .strong: activeStrong = lower..<upper
            case .emphasis: activeEmphasis = lower..<upper
            default: break
            }
            let context = FontContext(
                headingLevel: activeHeading.flatMap { $0.range.contains(lower) ? $0.level : nil },
                inStrong: activeStrong?.contains(lower) == true,
                inEmphasis: activeEmphasis?.contains(lower) == true
            )

            let start = utf8.index(cursorIndex, offsetBy: lower - cursorOffset)
            let end = utf8.index(start, offsetBy: upper - lower)
            text[start..<end].mergeAttributes(container(for: run.style, fontSize: fontSize, context: context))
            cursorOffset = lower
            cursorIndex = start
        }
    }

    // MARK: - Style resolution

    private static let headingScales: [CGFloat] = [1.6, 1.4, 1.25, 1.15, 1.05, 1.0]

    /// Ambient formatting at a run's position. SwiftUI `Font` attributes
    /// replace rather than merge, so nested inline styles (bold inside a
    /// heading, emphasis inside strong) must resolve to a single font here.
    private struct FontContext {
        var headingLevel: Int?
        var inStrong: Bool
        var inEmphasis: Bool
    }

    private static func scale(forHeadingLevel level: Int) -> CGFloat {
        headingScales[min(max(level, 1), 6) - 1]
    }

    private static func container(for style: Style, fontSize: CGFloat, context: FontContext) -> AttributeContainer {
        let size = fontSize * (context.headingLevel.map(scale(forHeadingLevel:)) ?? 1)
        var c = AttributeContainer()
        switch style {
        case .heading(let level):
            c.font = .system(size: fontSize * scale(forHeadingLevel: level), weight: .bold)
        case .strong:
            var font = Font.system(size: size, weight: context.headingLevel == nil ? .bold : .heavy)
            if context.inEmphasis { font = font.italic() }
            c.font = font
        case .emphasis:
            let weight: Font.Weight = (context.headingLevel != nil || context.inStrong) ? .bold : .regular
            c.font = .system(size: size, weight: weight).italic()
        case .inlineCode:
            c.font = .system(size: max(size - 1, 4), design: .monospaced)
            c.backgroundColor = Color.gray.opacity(0.15)
        case .codeBlock:
            c.font = .system(size: max(fontSize - 1, 4), design: .monospaced)
        case .link:
            c.foregroundColor = .accentColor
            c.underlineStyle = .single
        case .blockQuote:
            c.foregroundColor = .secondary
        case .listMarker, .syntaxMarker:
            c.foregroundColor = .secondary
        case .thematicBreak:
            c.foregroundColor = Color.secondary.opacity(0.5)
        }
        return c
    }
}

// MARK: - Walker

/// Walks the swift-markdown AST emitting style runs. Node `SourceRange`s are
/// 1-based line/column pairs with UTF-8-byte columns (cmark-gfm semantics);
/// a line-offset table converts them to flat UTF-8 offsets. Nodes without
/// ranges are skipped; all offsets are clamped, so a surprising range renders
/// unstyled rather than crashing.
private struct RunWalker: MarkupWalker {
    var runs: [MarkdownStyler.StyleRun] = []
    private let bytes: [UInt8]
    private let lineStarts: [Int]

    init(source: String) {
        bytes = Array(source.utf8)
        var starts = [0]
        for (index, byte) in bytes.enumerated() where byte == 0x0A {
            starts.append(index + 1)
        }
        lineStarts = starts
    }

    // MARK: Visits

    mutating func visitHeading(_ heading: Heading) {
        if let range = utf8Range(of: heading) {
            runs.append(.init(utf8Range: range, style: .heading(level: heading.level)))
            appendGapMarkers(for: heading, in: range)
        }
        descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
        if let range = utf8Range(of: strong) {
            runs.append(.init(utf8Range: range, style: .strong))
            appendGapMarkers(for: strong, in: range)
        }
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        if let range = utf8Range(of: emphasis) {
            runs.append(.init(utf8Range: range, style: .emphasis))
            appendGapMarkers(for: emphasis, in: range)
        }
        descendInto(emphasis)
    }

    mutating func visitLink(_ link: Markdown.Link) {
        if let range = utf8Range(of: link) {
            runs.append(.init(utf8Range: range, style: .link))
            appendGapMarkers(for: link, in: range)
        }
        descendInto(link)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        guard let range = utf8Range(of: inlineCode) else { return }
        runs.append(.init(utf8Range: range, style: .inlineCode))
        // No ranged children: derive the backtick delimiters by scanning.
        var lead = range.lowerBound
        while lead < range.upperBound, bytes[lead] == UInt8(ascii: "`") { lead += 1 }
        var trail = range.upperBound
        while trail > lead, bytes[trail - 1] == UInt8(ascii: "`") { trail -= 1 }
        if lead > range.lowerBound {
            runs.append(.init(utf8Range: range.lowerBound..<lead, style: .syntaxMarker))
        }
        if trail < range.upperBound {
            runs.append(.init(utf8Range: trail..<range.upperBound, style: .syntaxMarker))
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let range = utf8Range(of: codeBlock) {
            runs.append(.init(utf8Range: range, style: .codeBlock))
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if let range = utf8Range(of: blockQuote) {
            runs.append(.init(utf8Range: range, style: .blockQuote))
            appendQuoteMarkers(in: range)
        }
        descendInto(blockQuote)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let range = utf8Range(of: listItem),
           let firstChildStart = listItem.children.compactMap({ utf8Range(of: $0)?.lowerBound }).min(),
           firstChildStart > range.lowerBound {
            runs.append(.init(utf8Range: range.lowerBound..<firstChildStart, style: .listMarker))
        }
        descendInto(listItem)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        if let range = utf8Range(of: thematicBreak) {
            runs.append(.init(utf8Range: range, style: .thematicBreak))
        }
    }

    // MARK: Marker derivation

    /// Delimiters of container nodes (`**`, `*`, `[`, `](url)`, `# `) are the
    /// gaps between the node's range and the union of its children's ranges.
    private mutating func appendGapMarkers(for markup: Markup, in range: Range<Int>) {
        let childRanges = markup.children
            .compactMap { utf8Range(of: $0) }
            .sorted { $0.lowerBound < $1.lowerBound }
        guard !childRanges.isEmpty else { return }
        var cursor = range.lowerBound
        for child in childRanges {
            if child.lowerBound > cursor {
                runs.append(.init(utf8Range: cursor..<child.lowerBound, style: .syntaxMarker))
            }
            cursor = max(cursor, child.upperBound)
        }
        if cursor < range.upperBound {
            runs.append(.init(utf8Range: cursor..<range.upperBound, style: .syntaxMarker))
        }
    }

    /// The `>` repeats on every quoted line and children's ranges exclude it,
    /// so scan each line in the quote for its leading marker.
    private mutating func appendQuoteMarkers(in range: Range<Int>) {
        for lineStart in lineStarts[lineIndex(containing: range.lowerBound)...] {
            guard lineStart < range.upperBound else { break }
            var i = max(lineStart, range.lowerBound)
            var spaces = 0
            while i < range.upperBound, bytes[i] == UInt8(ascii: " "), spaces < 3 {
                i += 1
                spaces += 1
            }
            guard i < range.upperBound, bytes[i] == UInt8(ascii: ">") else { continue }
            var end = i + 1
            if end < range.upperBound, bytes[end] == UInt8(ascii: " ") { end += 1 }
            runs.append(.init(utf8Range: i..<end, style: .syntaxMarker))
        }
    }

    // MARK: Offset conversion

    private func utf8Range(of markup: Markup) -> Range<Int>? {
        guard let sourceRange = markup.range else { return nil }
        let lower = utf8Offset(of: sourceRange.lowerBound)
        let upper = utf8Offset(of: sourceRange.upperBound)
        guard lower <= upper else { return nil }
        return lower..<upper
    }

    private func utf8Offset(of location: SourceLocation) -> Int {
        let lineIndex = location.line - 1
        guard lineIndex >= 0 else { return 0 }
        guard lineIndex < lineStarts.count else { return bytes.count }
        return min(max(lineStarts[lineIndex] + location.column - 1, 0), bytes.count)
    }

    private func lineIndex(containing offset: Int) -> Int {
        var index = 0
        for (i, start) in lineStarts.enumerated() where start <= offset {
            index = i
        }
        return index
    }
}
