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
