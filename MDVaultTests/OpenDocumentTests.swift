import Foundation
import Testing
@testable import MDVault

/// Behavioral coverage of the save pipeline against real files: atomic
/// writes, the clobber-refusing pre-check, adopt, and deliberate overwrite.
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

        document.save()
        #expect(document.conflict)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# start\nagent edit")
    }

    @Test func saveAdoptsWhenDiskMatchesBuffer() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nsame edit")
        try "# start\nsame edit".write(to: url, atomically: true, encoding: .utf8)

        document.save()
        #expect(!document.conflict)
        #expect(!document.isDirty)
    }

    @Test func keepMineOverwritesDeliberately() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nmy edit")
        try "# start\nagent edit".write(to: url, atomically: true, encoding: .utf8)
        document.save()
        #expect(document.conflict)

        document.keepMine()
        #expect(!document.conflict)
        #expect(!document.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "# start\nmy edit")
    }

    @Test func reloadReplacesBufferAndCleans() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        document.noteEdit("# start\nmy edit")
        document.conflict = true
        document.reload(source: "# agent version", fontSize: 14)

        #expect(String(document.text.characters) == "# agent version")
        #expect(!document.isDirty)
        #expect(!document.conflict)
    }

    @Test func cleanSaveIsANoOp() throws {
        let (document, url) = try makeDocument()
        defer { try? FileManager.default.removeItem(at: url) }

        let before = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
        document.save()
        let after = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(before == after)
    }
}
