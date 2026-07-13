import SwiftUI

/// Editor state for a single open markdown file.
///
/// `text` is the TextEditor binding; its characters are always the raw markdown
/// source. `plainText` caches `String(text.characters)` and is the single
/// mechanism for both re-entrancy guarding (attribute-only restyles leave it
/// untouched) and dirty detection (compare against `lastSavedText`).
@MainActor @Observable
final class OpenDocument {
    private(set) var url: URL
    var text: AttributedString
    var selection = AttributedTextSelection()
    private(set) var plainText: String
    private(set) var lastSavedText: String
    var conflict = false
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

    /// Record a real (character) edit detected by the editor's onChange guard.
    func noteEdit(_ newPlainText: String) {
        plainText = newPlainText
        editGeneration += 1
    }

    /// Re-derive styling from the current source. Attribute-only mutation:
    /// character content is untouched, so character offsets stay valid.
    ///
    /// The selection is captured as character offsets and rebuilt afterward.
    /// `transform(updating:)` is supposed to remap the selection across the
    /// mutation, but on macOS 26.5 a mid-document insertion point ends up at
    /// the end of the document after a whole-string setAttributes, so we
    /// re-derive it ourselves (verified via the M1 accessibility harness).
    func restyle(fontSize: CGFloat) {
        let runs = MarkdownStyler.runs(for: plainText)
        let captured = capturedSelectionOffsets()
        MarkdownStyler.applyRuns(runs, to: &text, fontSize: fontSize)
        restoreSelection(from: captured)
    }

    // MARK: - Disk

    /// Autosave and save-on-switch path. Refuses to clobber an unprocessed
    /// external write; that becomes a conflict instead.
    func save() {
        guard isDirty else { return }
        if let diskContent = try? String(contentsOf: url, encoding: .utf8), diskContent != lastSavedText {
            if diskContent == plainText {
                adoptDiskContent(diskContent)
            } else {
                conflict = true
            }
            return
        }
        write()
    }

    /// Explicit Cmd-S. During a conflict this is the deliberate overwrite.
    func saveCommand() {
        if conflict {
            keepMine()
        } else {
            save()
        }
    }

    /// Resolve a conflict in favor of the buffer: overwrite the file now.
    func keepMine() {
        conflict = false
        write()
    }

    /// Resolve a conflict by discarding the buffer for the disk content.
    func reloadFromDisk(fontSize: CGFloat) {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        reload(source: source, fontSize: fontSize)
    }

    /// Replace the buffer with new disk content. Whole-string replacement;
    /// the selection reset is correct because the content changed under us.
    func reload(source: String, fontSize: CGFloat) {
        plainText = source
        lastSavedText = source
        conflict = false
        text = MarkdownStyler.styledText(source, fontSize: fontSize)
        selection = AttributedTextSelection()
    }

    /// An external write landed with exactly the buffer's content; nothing
    /// changes on screen, the buffer is simply clean now.
    func adoptDiskContent(_ diskContent: String) {
        lastSavedText = diskContent
        conflict = false
    }

    /// The file moved (a rename of it or of an ancestor folder).
    func relocate(to newURL: URL) {
        url = newURL
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }

    private func write() {
        do {
            try Data(plainText.utf8).write(to: url, options: .atomic)
            lastSavedText = plainText
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = "Could not save \(fileName): \(error.localizedDescription)"
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
