import Foundation

struct VaultItem: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isMarkdown: Bool
    let children: [VaultItem]?

    var id: URL { url }

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

    static func path(of url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func topLevelURLs(_ urls: some Sequence<URL>) -> [URL] {
        let sorted = Set(urls.map(\.standardizedFileURL)).sorted {
            let lhs = path(of: $0)
            let rhs = path(of: $1)
            return lhs.count != rhs.count ? lhs.count < rhs.count : lhs < rhs
        }
        return sorted.filter { candidate in
            let candidatePath = path(of: candidate)
            return !sorted.contains { other in
                let otherPath = path(of: other)
                return otherPath != candidatePath && candidatePath.hasPrefix(otherPath + "/")
            }
        }
    }

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

    static func importDestination(for source: URL, into directory: URL, vaultURL: URL) -> URL? {
        let sourcePath = path(of: source)
        let directoryPath = path(of: directory)
        let vaultPath = path(of: vaultURL)
        guard directoryPath == vaultPath || directoryPath.hasPrefix(vaultPath + "/") else { return nil }

        let destination = URL(filePath: directoryPath, directoryHint: .isDirectory)
            .appending(path: source.lastPathComponent)
            .standardizedFileURL
        let destinationPath = path(of: destination)
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else { return nil }
        return destination
    }
}
