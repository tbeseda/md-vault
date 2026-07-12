import Foundation

/// One node of the vault's file tree. `children` is nil for files so that
/// outline views show no disclosure chevron.
struct VaultItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isMarkdown: Bool
    let children: [VaultItem]?

    var id: URL { url }

    /// Scan a directory into a sorted tree: folders first, then files, each
    /// Finder-style. Dotfiles are hidden; other non-markdown files are kept
    /// (agents drop images and JSON next to notes) and rendered dimmed.
    static func buildTree(at directory: URL) -> [VaultItem] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries
            .map { $0.standardizedFileURL }
            .compactMap { url -> VaultItem? in
                let name = url.lastPathComponent
                guard !name.hasPrefix(".") else { return nil }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    return VaultItem(url: url, name: name, isDirectory: true, isMarkdown: false, children: buildTree(at: url))
                }
                return VaultItem(
                    url: url,
                    name: name,
                    isDirectory: false,
                    isMarkdown: name.lowercased().hasSuffix(".md"),
                    children: nil
                )
            }
            .sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }
}
