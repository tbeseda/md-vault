import Foundation
import Testing
@testable import MDVault

@MainActor
struct AppStateTests {
    @Test func conflictPreventsSwitchingFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()
        let document = try #require(fixture.state.openDocument)
        document.noteEdit("# local edit")
        try "# external edit".write(to: fixture.firstFile, atomically: true, encoding: .utf8)

        fixture.state.activeFileURL = fixture.secondFile
        fixture.state.openActiveFile(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.firstFile)
        #expect(fixture.state.selectedItemURLs == [fixture.firstFile])
        #expect(fixture.state.openDocument === document)
        #expect(document.plainText == "# local edit")
        #expect(document.conflict == .modified)
    }

    @Test func externalDeletionPreservesDirtyDocument() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()
        let document = try #require(fixture.state.openDocument)
        document.noteEdit("# local edit")
        try FileManager.default.removeItem(at: fixture.firstFile)

        fixture.state.handleExternalChanges(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.firstFile)
        #expect(fixture.state.openDocument === document)
        #expect(document.plainText == "# local edit")
        #expect(document.conflict == .deleted)
    }

    @Test func conflictPreventsClosingVault() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()
        let document = try #require(fixture.state.openDocument)
        document.noteEdit("# local edit")
        try "# external edit".write(to: fixture.firstFile, atomically: true, encoding: .utf8)

        fixture.state.closeVault()

        #expect(fixture.state.vaultURL == fixture.root)
        #expect(fixture.state.openDocument === document)
        #expect(document.conflict == .modified)
    }

    @Test func externalDeletionClosesCleanDocument() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()
        try FileManager.default.removeItem(at: fixture.firstFile)

        fixture.state.handleExternalChanges(fontSize: 14)

        #expect(fixture.state.activeFileURL == nil)
        #expect(fixture.state.openDocument == nil)
    }

    @Test func selectingMarkdownFileActivatesIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()

        fixture.state.selectedItemURLs = [fixture.secondFile]
        fixture.state.selectionDidChange(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.secondFile)
    }

    // The restore used to land an observation hop later, after a rapid second
    // click had already written a new selection.
    @Test func conflictRestoresSelectionWithinTheSameSelectionChange() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()
        let document = try #require(fixture.state.openDocument)
        document.noteEdit("# local edit")
        try "# external edit".write(to: fixture.firstFile, atomically: true, encoding: .utf8)

        fixture.state.selectedItemURLs = [fixture.secondFile]
        fixture.state.selectionDidChange(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.firstFile)
        #expect(fixture.state.selectedItemURLs == [fixture.firstFile])
        #expect(fixture.state.openDocument === document)
        #expect(document.conflict == .modified)
    }

    @Test func extendingSelectionKeepsActiveMarkdown() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()

        fixture.state.selectedItemURLs.insert(fixture.secondFile)
        fixture.state.selectionDidChange(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.firstFile)
    }

    @Test func rangeSelectionKeepsActiveMarkdownWhenStillSelected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()

        fixture.state.selectedItemURLs = [fixture.firstFile, fixture.secondFile]
        fixture.state.selectionDidChange(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.firstFile)
    }

    @Test func selectingNonMarkdownItemKeepsDocumentOpen() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.openFirstFile()
        let document = try #require(fixture.state.openDocument)
        let asset = fixture.root.appending(path: "image.png")
        try Data([0, 1, 2]).write(to: asset)
        fixture.state.rescanTree()

        fixture.state.selectedItemURLs = [asset]
        fixture.state.selectionDidChange(fontSize: 14)

        #expect(fixture.state.activeFileURL == fixture.firstFile)
        #expect(fixture.state.openDocument === document)
    }

    @Test func internalDropMovesFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let folder = fixture.root.appending(path: "archive", directoryHint: .isDirectory)
        let destination = folder.appending(path: fixture.firstFile.lastPathComponent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        fixture.state.rescanTree()

        #expect(fixture.state.receiveDrop([fixture.firstFile], into: folder))

        #expect(!FileManager.default.fileExists(atPath: fixture.firstFile.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
        #expect(fixture.state.selectedItemURLs == [destination])
    }

    @Test func externalDropCopiesFileAndFolder() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let sourceRoot = FileManager.default.temporaryDirectory
            .appending(path: "drop-\(UUID().uuidString)", directoryHint: .isDirectory)
        let file = sourceRoot.appending(path: "asset.txt")
        let folder = sourceRoot.appending(path: "notes", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "asset".write(to: file, atomically: true, encoding: .utf8)
        try "# nested".write(to: folder.appending(path: "nested.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sourceRoot) }

        #expect(fixture.state.receiveDrop([file, folder], into: fixture.root))

        #expect(try String(contentsOf: fixture.root.appending(path: "asset.txt"), encoding: .utf8) == "asset")
        #expect(try String(contentsOf: fixture.root.appending(path: "notes/nested.md"), encoding: .utf8) == "# nested")
        #expect(fixture.state.selectedItemURLs == [
            fixture.root.appending(path: "asset.txt"),
            fixture.root.appending(path: "notes")
        ])
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let firstFile: URL
        let secondFile: URL
        let state: AppState
        private let defaults: UserDefaults
        private let suiteName: String

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "vault-\(UUID().uuidString)", directoryHint: .isDirectory)
            firstFile = root.appending(path: "first.md")
            secondFile = root.appending(path: "second.md")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            try "# first".write(to: firstFile, atomically: true, encoding: .utf8)
            try "# second".write(to: secondFile, atomically: true, encoding: .utf8)

            suiteName = "MDVaultTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            state = AppState(defaults: defaults)
            state.openVault(at: root)
        }

        func openFirstFile() {
            state.selectedItemURLs = [firstFile]
            state.activeFileURL = firstFile
            state.openActiveFile(fontSize: 14)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
