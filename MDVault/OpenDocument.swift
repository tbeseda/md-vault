import SwiftUI

@MainActor @Observable
final class OpenDocument {
    enum Conflict: Equatable, Sendable {
        case modified
        case deleted
    }

    private(set) var url: URL
    var text: AttributedString
    var selection = AttributedTextSelection()
    private(set) var plainText: String
    private(set) var lastSavedText: String
    var conflict: Conflict?
    private(set) var editGeneration = 0
    private(set) var saveErrorMessage: String?

    var isDirty: Bool { plainText != lastSavedText }
    var fileName: String { url.lastPathComponent }

    init(url: URL, source: String, fontSize: CGFloat) {
        self.url = url
        plainText = source
        lastSavedText = source
        text = MarkdownStyler.styledText(source, fontSize: fontSize)
    }

    // MARK: - Editing

    func noteEdit(_ newPlainText: String) {
        plainText = newPlainText
        editGeneration += 1
    }

    func continueList() -> Bool {
        guard case .insertionPoint(let insertionPoint) = selection.indices(in: text) else { return false }
        let characters = text.characters
        let offset = characters.distance(from: characters.startIndex, to: insertionPoint)
        guard let edit = MarkdownListContinuation.edit(in: plainText, at: offset) else { return false }

        let sourceLower = plainText.index(plainText.startIndex, offsetBy: edit.replacementRange.lowerBound)
        let sourceUpper = plainText.index(plainText.startIndex, offsetBy: edit.replacementRange.upperBound)
        plainText.replaceSubrange(sourceLower..<sourceUpper, with: edit.replacement)
        editGeneration += 1

        let textLower = text.index(text.startIndex, offsetByCharacters: edit.replacementRange.lowerBound)
        let textUpper = text.index(text.startIndex, offsetByCharacters: edit.replacementRange.upperBound)
        text.replaceSubrange(textLower..<textUpper, with: AttributedString(edit.replacement))
        let restored = text.index(text.startIndex, offsetByCharacters: edit.insertionOffset)
        selection = AttributedTextSelection(insertionPoint: restored)
        return true
    }

    // transform(updating:) moves a mid-document insertion point to the end
    // after whole-string setAttributes on macOS 26.5.
    func restyle(fontSize: CGFloat) {
        let runs = MarkdownStyler.runs(for: plainText)
        let captured = capturedSelectionOffsets()
        MarkdownStyler.applyRuns(runs, to: &text, fontSize: fontSize)
        restoreSelection(from: captured)
    }

    // MARK: - Disk

    @discardableResult
    func save() -> Bool {
        guard isDirty else { return true }

        let diskContent: String
        do {
            diskContent = try String(contentsOf: url, encoding: .utf8)
        } catch {
            if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                saveErrorMessage = "Could not read \(fileName) before saving: \(error.localizedDescription)"
            } else {
                conflict = .deleted
            }
            return false
        }

        if diskContent != lastSavedText {
            if diskContent == plainText {
                adoptDiskContent(diskContent)
                return true
            } else {
                conflict = .modified
                return false
            }
        }
        return write()
    }

    func saveCommand() {
        if conflict != nil {
            keepMine()
        } else {
            save()
        }
    }

    func keepMine() {
        conflict = nil
        write()
    }

    func reloadFromDisk(fontSize: CGFloat) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        reload(source: source, fontSize: fontSize)
    }

    func reload(source: String, fontSize: CGFloat) {
        plainText = source
        lastSavedText = source
        conflict = nil
        text = MarkdownStyler.styledText(source, fontSize: fontSize)
        selection = AttributedTextSelection()
    }

    func adoptDiskContent(_ diskContent: String) {
        lastSavedText = diskContent
        conflict = nil
    }

    func relocate(to newURL: URL) {
        url = newURL
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }

    @discardableResult
    private func write() -> Bool {
        do {
            try Data(plainText.utf8).write(to: url, options: .atomic)
            lastSavedText = plainText
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = "Could not save \(fileName): \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Selection preservation

    private enum SelectionOffsets {
        case insertionPoint(Int)
        case ranges([(Int, Int)])
    }

    private func capturedSelectionOffsets() -> SelectionOffsets {
        let chars = text.characters
        switch selection.indices(in: text) {
        case .insertionPoint(let index):
            return .insertionPoint(chars.distance(from: chars.startIndex, to: index))
        case .ranges(let rangeSet):
            return .ranges(rangeSet.ranges.map { range in
                (chars.distance(from: chars.startIndex, to: range.lowerBound),
                 chars.distance(from: chars.startIndex, to: range.upperBound))
            })
        }
    }

    private func restoreSelection(from offsets: SelectionOffsets) {
        let count = text.characters.count
        func index(at offset: Int) -> AttributedString.Index {
            text.index(text.startIndex, offsetByCharacters: min(max(offset, 0), count))
        }
        switch offsets {
        case .insertionPoint(let offset):
            selection = AttributedTextSelection(insertionPoint: index(at: offset))
        case .ranges(let pairs):
            var rangeSet = RangeSet<AttributedString.Index>()
            for (lower, upper) in pairs where lower < upper {
                rangeSet.insert(contentsOf: index(at: lower)..<index(at: upper))
            }
            selection = AttributedTextSelection(ranges: rangeSet)
        }
    }
}

enum MarkdownListContinuation {
    struct Edit: Equatable, Sendable {
        let replacementRange: Range<Int>
        let replacement: String
        let insertionOffset: Int
    }

    static func edit(in source: String, at insertionOffset: Int) -> Edit? {
        guard insertionOffset >= 0, insertionOffset <= source.count else { return nil }
        let insertionIndex = source.index(source.startIndex, offsetBy: insertionOffset)
        let lineStart = source[..<insertionIndex].lastIndex(of: "\n").map { source.index(after: $0) } ?? source.startIndex
        let lineEnd = source[insertionIndex...].firstIndex(of: "\n") ?? source.endIndex
        let line = String(source[lineStart..<lineEnd])
        let offsetInLine = source.distance(from: lineStart, to: insertionIndex)
        guard let prefix = prefix(in: line), offsetInLine >= prefix.contentOffset else { return nil }

        let contentStart = line.index(line.startIndex, offsetBy: prefix.contentOffset)
        if line[contentStart...].trimmingCharacters(in: .whitespaces).isEmpty {
            let lineStartOffset = source.distance(from: source.startIndex, to: lineStart)
            return Edit(
                replacementRange: lineStartOffset..<(lineStartOffset + prefix.contentOffset),
                replacement: "",
                insertionOffset: lineStartOffset
            )
        }

        let replacement = "\n" + prefix.next
        return Edit(
            replacementRange: insertionOffset..<insertionOffset,
            replacement: replacement,
            insertionOffset: insertionOffset + replacement.count
        )
    }

    private struct Prefix {
        let contentOffset: Int
        let next: String
    }

    private static func prefix(in line: String) -> Prefix? {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        let indentation = String(line[..<index])

        let marker: String
        let nextMarker: String
        if index < line.endIndex, "-*+".contains(line[index]) {
            marker = String(line[index])
            nextMarker = marker
            index = line.index(after: index)
        } else {
            let numberStart = index
            while index < line.endIndex, line[index].isNumber {
                index = line.index(after: index)
            }
            guard numberStart < index,
                  index < line.endIndex,
                  line[index] == "." || line[index] == ")",
                  let number = Int(line[numberStart..<index])
            else { return nil }
            let delimiter = line[index]
            marker = String(line[numberStart...index])
            let (nextNumber, overflow) = number.addingReportingOverflow(1)
            nextMarker = overflow ? marker : "\(nextNumber)\(delimiter)"
            index = line.index(after: index)
        }

        let spacingStart = index
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        guard spacingStart < index else { return nil }
        let markerSpacing = String(line[spacingStart..<index])

        var taskPrefix: String?
        if line[index...].hasPrefix("[ ]") || line[index...].hasPrefix("[x]") || line[index...].hasPrefix("[X]") {
            let taskEnd = line.index(index, offsetBy: 3)
            guard taskEnd == line.endIndex || line[taskEnd] == " " || line[taskEnd] == "\t" else { return nil }
            index = taskEnd
            let taskSpacingStart = index
            while index < line.endIndex, line[index] == " " || line[index] == "\t" {
                index = line.index(after: index)
            }
            let taskSpacing = taskSpacingStart < index ? String(line[taskSpacingStart..<index]) : " "
            taskPrefix = "[ ]" + taskSpacing
        }

        return Prefix(
            contentOffset: line.distance(from: line.startIndex, to: index),
            next: indentation + nextMarker + markerSpacing + (taskPrefix ?? "")
        )
    }
}
