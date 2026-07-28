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

        fixture.state.selectedFileURL = fixture.secondFile
        fixture.state.openSelectedFile(fontSize: 14)

        #expect(fixture.state.selectedFileURL == fixture.firstFile)
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

        #expect(fixture.state.selectedFileURL == fixture.firstFile)
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

        #expect(fixture.state.selectedFileURL == nil)
        #expect(fixture.state.openDocument == nil)
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
            state.selectedFileURL = firstFile
            state.openSelectedFile(fontSize: 14)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}
