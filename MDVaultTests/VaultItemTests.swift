import Foundation
import Testing
@testable import MDVault

struct VaultItemTests {
    @Test func buildsSortedFilteredTree() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "vault-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root.appending(path: "b-folder"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appending(path: ".obsidian"), withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try "# a".write(to: root.appending(path: "zeta.md"), atomically: true, encoding: .utf8)
        try "# b".write(to: root.appending(path: "Alpha.MD"), atomically: true, encoding: .utf8)
        try Data().write(to: root.appending(path: "image.png"))
        try "x".write(to: root.appending(path: ".hidden"), atomically: true, encoding: .utf8)
        try "# n".write(to: root.appending(path: "b-folder/nested.md"), atomically: true, encoding: .utf8)

        let tree = VaultItem.buildTree(at: root)

        #expect(tree.map(\.name) == ["b-folder", "Alpha.MD", "image.png", "zeta.md"])
        #expect(!tree.contains { $0.name.hasPrefix(".") })

        let folder = try #require(tree.first)
        #expect(folder.isDirectory)
        #expect(folder.children?.map(\.name) == ["nested.md"])

        let alpha = tree[1]
        #expect(alpha.isMarkdown)
        #expect(alpha.children == nil)
        #expect(!tree[2].isMarkdown)
    }

    @Test func missingDirectoryYieldsEmptyTree() {
        let bogus = URL(filePath: "/nonexistent/\(UUID().uuidString)")
        #expect(VaultItem.buildTree(at: bogus).isEmpty)
    }

    // MARK: - moveDestination (pure planning; no filesystem)

    private let vault = URL(filePath: "/tmp/vault")

    private func plan(_ source: String, into directory: String) -> String? {
        VaultItem.moveDestination(
            for: URL(filePath: source),
            into: URL(filePath: directory),
            vaultURL: vault
        )?.path(percentEncoded: false)
    }

    @Test func movesFileIntoFolder() {
        #expect(plan("/tmp/vault/a.md", into: "/tmp/vault/dir") == "/tmp/vault/dir/a.md")
    }

    @Test func movesNestedFileToVaultRoot() {
        #expect(plan("/tmp/vault/dir/a.md", into: "/tmp/vault") == "/tmp/vault/a.md")
    }

    @Test func movesFolderIntoSiblingFolder() {
        #expect(plan("/tmp/vault/dir", into: "/tmp/vault/other") == "/tmp/vault/other/dir")
    }

    @Test func ignoresSameParentMove() {
        #expect(plan("/tmp/vault/dir/a.md", into: "/tmp/vault/dir") == nil)
        #expect(plan("/tmp/vault/a.md", into: "/tmp/vault") == nil)
    }

    @Test func ignoresFolderIntoItselfOrDescendant() {
        #expect(plan("/tmp/vault/dir", into: "/tmp/vault/dir") == nil)
        #expect(plan("/tmp/vault/dir", into: "/tmp/vault/dir/sub") == nil)
    }

    @Test func ignoresSourcesOutsideVault() {
        #expect(plan("/tmp/elsewhere/a.md", into: "/tmp/vault/dir") == nil)
        #expect(plan("/tmp/vault", into: "/tmp/vault/dir") == nil)
        // Sibling path sharing the vault's name as a prefix is still outside.
        #expect(plan("/tmp/vault-other/a.md", into: "/tmp/vault/dir") == nil)
    }

    @Test func ignoresTargetsOutsideVault() {
        #expect(plan("/tmp/vault/a.md", into: "/tmp/elsewhere") == nil)
        #expect(plan("/tmp/vault/a.md", into: "/tmp/vault-other") == nil)
    }

    @Test func trailingSlashAndDirectoryHintsDoNotConfusePlanning() {
        let destination = VaultItem.moveDestination(
            for: URL(filePath: "/tmp/vault/dir/", directoryHint: .isDirectory),
            into: URL(filePath: "/tmp/vault/other/", directoryHint: .isDirectory),
            vaultURL: URL(filePath: "/tmp/vault/", directoryHint: .isDirectory)
        )
        #expect(destination?.path(percentEncoded: false) == "/tmp/vault/other/dir")
    }
}
