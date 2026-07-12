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
}
