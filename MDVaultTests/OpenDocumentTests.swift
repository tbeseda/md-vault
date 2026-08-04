import Foundation
import SwiftUI
import Testing
@testable import MDVault

@MainActor
struct OpenDocumentTests {
    private func makeDocument(content: String = "# start") throws -> (OpenDocument, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "doc-\(UUID().uuidString).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return (OpenDocument(url: url, source: content, fontSize: 14), url)
    }

    @Test func saveWritesDirtyBufferAndCleans() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nedited")
        #expect(document.isDirty)
        document.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == "# start\nedited")
        #expect(!document.isDirty)
    }

    @Test func saveRefusesToClobberExternalWrite() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nmy edit")
        try "# start\nagent edit".write(to: url, atomically: true, encoding: .utf8)

        #expect(!document.save())
        #expect(document.conflict == .modified)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# start\nagent edit")
    }

    @Test func saveAdoptsWhenDiskMatchesBuffer() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nsame edit")
        try "# start\nsame edit".write(to: url, atomically: true, encoding: .utf8)

        #expect(document.save())
        #expect(document.conflict == nil)
        #expect(!document.isDirty)
    }

    @Test func keepMineOverwritesDeliberately() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nmy edit")
        try "# start\nagent edit".write(to: url, atomically: true, encoding: .utf8)
        document.save()
        #expect(document.conflict == .modified)

        document.keepMine()
        #expect(document.conflict == nil)
        #expect(!document.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# start\nmy edit")
    }

    @Test func reloadReplacesBufferAndCleans() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nmy edit")
        document.conflict = .modified
        document.reload(source: "# agent version", fontSize: 14)

        #expect(String(document.text.characters) == "# agent version")
        #expect(!document.isDirty)
        #expect(document.conflict == nil)
    }

    @Test func cleanSaveIsANoOp() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
        document.save()
        let after = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(before == after)
    }

    @Test func saveDoesNotRecreateDeletedFile() throws {
        let (document, url) = try makeDocument()
        document.noteEdit("# local edit")
        try FileManager.default.removeItem(at: url)

        #expect(!document.save())
        #expect(document.conflict == .deleted)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func keepMineRecreatesDeletedFile() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }
        document.noteEdit("# local edit")
        try FileManager.default.removeItem(at: url)
        document.save()

        document.keepMine()

        #expect(document.conflict == nil)
        #expect(!document.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# local edit")
    }

    @Test(arguments: [
        ("- item", "- item\n- "),
        ("* item", "* item\n* "),
        ("+ item", "+ item\n+ "),
        ("9. item", "9. item\n10. "),
        ("2) item", "2) item\n3) "),
        ("  - item", "  - item\n  - "),
        ("- [x] done", "- [x] done\n- [ ] "),
        ("1. [X] done", "1. [X] done\n2. [ ] ")
    ])
    func continuesMarkdownList(argument: (source: String, expected: String)) throws {
        let edit = try #require(MarkdownListContinuation.edit(in: argument.source, at: argument.source.count))
        #expect(applying(edit, to: argument.source) == argument.expected)
        #expect(edit.insertionOffset == argument.expected.count)
    }

    @Test func exitsEmptyListItem() throws {
        let source = "- item\n  - [ ] "
        let edit = try #require(MarkdownListContinuation.edit(in: source, at: source.count))

        #expect(applying(edit, to: source) == "- item\n")
        #expect(edit.insertionOffset == "- item\n".count)
    }

    @Test func splitsListItemAtCaret() throws {
        let source = "- ab"
        let edit = try #require(MarkdownListContinuation.edit(in: source, at: 3))

        #expect(applying(edit, to: source) == "- a\n- b")
    }

    @Test func unicodeBeforeListKeepsCharacterOffsets() throws {
        let source = "🎉\n- café"
        let edit = try #require(MarkdownListContinuation.edit(in: source, at: source.count))

        #expect(applying(edit, to: source) == "🎉\n- café\n- ")
    }

    @Test func ignoresNonListAndCaretInsideMarker() {
        #expect(MarkdownListContinuation.edit(in: "paragraph", at: 9) == nil)
        #expect(MarkdownListContinuation.edit(in: "- item", at: 1) == nil)
    }

    @Test func documentContinuationUpdatesSourceSelectionAndDirtyState() throws {
        let (document, url) = try makeDocument(content: "- item")
        defer { try? FileManager.default.removeItem(at: url) }
        let end = document.text.endIndex
        document.selection = AttributedTextSelection(insertionPoint: end)

        #expect(document.continueList())
        #expect(document.plainText == "- item\n- ")
        #expect(String(document.text.characters) == document.plainText)
        #expect(document.isDirty)
        guard case .insertionPoint(let insertionPoint) = document.selection.indices(in: document.text) else {
            Issue.record("Expected an insertion point")
            return
        }
        #expect(insertionPoint == document.text.endIndex)
    }

    private func applying(_ edit: MarkdownListContinuation.Edit, to source: String) -> String {
        var result = source
        let lower = result.index(result.startIndex, offsetBy: edit.replacementRange.lowerBound)
        let upper = result.index(result.startIndex, offsetBy: edit.replacementRange.upperBound)
        result.replaceSubrange(lower..<upper, with: edit.replacement)
        return result
    }
}
