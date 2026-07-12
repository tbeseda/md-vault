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

    // MARK: - Drag-move planning

    /// A file URL's path without any trailing slash, for prefix/equality math.
    static func path(of url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Plan a drag-move of `source` into folder `directory`. Returns the
    /// destination URL, or nil for drops to ignore: sources from outside the
    /// vault (e.g. a Finder drag), targets outside the vault, a folder
    /// dropped into itself or a descendant, and same-parent moves (no-ops).
    /// Existence at the destination is the mover's concern, not the planner's.
    static func moveDestination(for source: URL, into directory: URL, vaultURL: URL) -> URL? {
        let sourcePath = path(of: source)
        let directoryPath = path(of: directory)
        let vaultPath = path(of: vaultURL)
        guard sourcePath.hasPrefix(vaultPath + "/"),
              directoryPath == vaultPath || directoryPath.hasPrefix(vaultPath + "/"),
              directoryPath != sourcePath,
              !directoryPath.hasPrefix(sourcePath + "/"),
              directoryPath != path(of: URL(filePath: sourcePath).deletingLastPathComponent())
        else { return nil }
        return URL(filePath: directoryPath, directoryHint: .isDirectory)
            .appending(path: source.lastPathComponent)
    }
}
