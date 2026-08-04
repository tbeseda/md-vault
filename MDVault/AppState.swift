import AppKit
import SwiftUI

@MainActor @Observable
final class AppState {
    private(set) var vaultURL: URL?
    private(set) var tree: [VaultItem] = []
    var selectedItemURLs = Set<URL>()
    var activeFileURL: URL?
    private(set) var openDocument: OpenDocument?
    private(set) var openError: String?
    var renamingItemURL: URL?
    private(set) var fileOpErrorMessage: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let path = defaults.string(forKey: "vaultPath") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                openVault(at: URL(filePath: path, directoryHint: .isDirectory))
            }
        }
        // SwiftUI has no scene-teardown hook for flushing the buffer on quit.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.openDocument?.save()
            }
        }
    }

    // MARK: - Vault

    // fileImporter cannot create a directory from the picker.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Vault"
        panel.message = "Choose a folder to use as your vault."
        if panel.runModal() == .OK, let url = panel.url {
            openVault(at: url)
        }
    }

    func openVault(at url: URL) {
        guard saveOpenDocumentBeforeClosing() else { return }
        vaultURL = url.standardizedFileURL
        defaults.set(url.path(percentEncoded: false), forKey: "vaultPath")
        selectedItemURLs = []
        activeFileURL = nil
        openDocument = nil
        openError = nil
        rescanTree()
    }

    func closeVault() {
        guard saveOpenDocumentBeforeClosing() else { return }
        defaults.removeObject(forKey: "vaultPath")
        vaultURL = nil
        tree = []
        selectedItemURLs = []
        activeFileURL = nil
        openDocument = nil
        openError = nil
        fileOpErrorMessage = nil
    }

    func rescanTree() {
        guard let vaultURL else {
            tree = []
            return
        }
        tree = VaultItem.buildTree(at: vaultURL)
        selectedItemURLs = Set(selectedItemURLs.filter(contains))
        if let activeFileURL, !contains(activeFileURL) {
            if let openDocument, openDocument.isDirty {
                openDocument.conflict = .deleted
            } else {
                self.activeFileURL = nil
                openDocument = nil
            }
        }
    }

    private func contains(_ url: URL) -> Bool {
        func search(_ items: [VaultItem]) -> Bool {
            items.contains { $0.url == url || search($0.children ?? []) }
        }
        return search(tree)
    }

    // MARK: - Document

    func openActiveFile(fontSize: CGFloat) {
        guard let url = activeFileURL else {
            guard saveOpenDocumentBeforeClosing() else { return }
            openDocument = nil
            openError = nil
            return
        }
        guard url != openDocument?.url else { return }
        guard saveOpenDocumentBeforeClosing() else { return }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            openDocument = OpenDocument(url: url, source: source, fontSize: fontSize)
            openError = nil
        } catch {
            openDocument = nil
            openError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Settles the whole selection-to-document transition before returning.
    ///
    /// A failed save restores both `activeFileURL` and `selectedItemURLs` to the
    /// conflicted document. Deferring the open to a separate observation of
    /// `activeFileURL` let that restore land after the next click had already
    /// written a new selection, stomping it.
    func selectionDidChange(fontSize: CGFloat) {
        let desired = desiredActiveFileURL()
        guard desired != activeFileURL else { return }
        activeFileURL = desired
        openActiveFile(fontSize: fontSize)
    }

    private func desiredActiveFileURL() -> URL? {
        if selectedItemURLs.count == 1,
           let url = selectedItemURLs.first,
           item(at: url)?.isMarkdown == true {
            return url
        }
        if activeFileURL.map(selectedItemURLs.contains) == true { return activeFileURL }
        return firstSelectedMarkdownURL(in: tree) ?? activeFileURL
    }

    func discardOpenDocument() {
        activeFileURL = nil
        openDocument = nil
        openError = nil
    }

    // MARK: - External changes

    func handleExternalChanges(fontSize: CGFloat) {
        rescanTree()
        guard let document = openDocument,
              let diskContent = try? String(contentsOf: document.url, encoding: .utf8) else { return }
        switch ExternalChange.determine(
            diskContent: diskContent,
            lastSavedText: document.lastSavedText,
            bufferText: document.plainText
        ) {
        case .ignoreEcho:
            break
        case .reload:
            document.reload(source: diskContent, fontSize: fontSize)
        case .adopt:
            document.adoptDiskContent(diskContent)
        case .conflict:
            document.conflict = .modified
        }
    }

    // MARK: - File operations

    func newFileRelativeToSelection() {
        let parent: URL?
        if selectedItemURLs.count == 1,
           let url = selectedItemURLs.first,
           let item = item(at: url) {
            parent = item.isDirectory ? item.url : item.url.deletingLastPathComponent()
        } else {
            parent = activeFileURL?.deletingLastPathComponent()
        }
        createFile(in: parent)
    }

    func createFile(in directory: URL?) {
        guard let parent = directory ?? vaultURL else { return }
        guard saveOpenDocumentBeforeClosing() else { return }
        let url = availableURL(in: parent, baseName: "Untitled", fileExtension: "md")
        do {
            try Data().write(to: url)
            rescanTree()
            selectedItemURLs = [url]
            activeFileURL = url
            renamingItemURL = url
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not create file: \(error.localizedDescription)"
        }
    }

    func createFolder(in directory: URL?) {
        guard let parent = directory ?? vaultURL else { return }
        let url = availableURL(in: parent, baseName: "New Folder", fileExtension: nil)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            rescanTree()
            selectedItemURLs = [url]
            renamingItemURL = url
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }

    func beginRenaming(_ item: VaultItem) {
        selectedItemURLs = [item.url]
        if item.isMarkdown {
            activeFileURL = item.url
        }
        renamingItemURL = item.url
    }

    func beginRenaming(_ urls: Set<URL>) {
        guard urls.count == 1,
              let url = urls.first,
              let item = item(at: url)
        else { return }
        beginRenaming(item)
    }

    func rename(_ item: VaultItem, to newName: String) {
        defer { renamingItemURL = nil }
        var trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !item.isDirectory, !trimmed.contains("."), !item.url.pathExtension.isEmpty {
            trimmed += "." + item.url.pathExtension
        }
        guard !trimmed.isEmpty, trimmed != item.name, !trimmed.contains("/") else { return }
        let destination = item.url.deletingLastPathComponent().appending(path: trimmed).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
            fileOpErrorMessage = "\(trimmed) already exists."
            return
        }
        do {
            try FileManager.default.moveItem(at: item.url, to: destination)
            if let updated = Self.adjustURL(openDocument?.url, from: item.url, to: destination) {
                openDocument?.relocate(to: updated)
            }
            if let updated = Self.adjustURL(activeFileURL, from: item.url, to: destination) {
                activeFileURL = updated
            }
            selectedItemURLs = Set(selectedItemURLs.map {
                Self.adjustURL($0, from: item.url, to: destination) ?? $0
            })
            rescanTree()
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not rename \(item.name): \(error.localizedDescription)"
        }
    }

    func copyFullPaths(_ urls: Set<URL>) {
        let value = urls.sorted {
            VaultItem.path(of: $0).localizedStandardCompare(VaultItem.path(of: $1)) == .orderedAscending
        }
            .map { VaultItem.path(of: $0) }
            .joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(value, forType: .string) {
            fileOpErrorMessage = "Could not copy the path to the clipboard."
        }
    }

    func showInFinder(_ urls: Set<URL>) {
        NSWorkspace.shared.activateFileViewerSelecting(Array(urls))
    }

    func trashSelection() {
        trash(Array(selectedItemURLs))
    }

    func trash(_ urls: [URL]) {
        let sources = VaultItem.topLevelURLs(urls)
        guard !sources.isEmpty else { return }
        var errors: [String] = []
        var trashed = false
        for source in sources {
            do {
                try FileManager.default.trashItem(at: source, resultingItemURL: nil)
                if Self.contains(openDocument?.url, in: source) {
                    activeFileURL = nil
                    openDocument = nil
                    openError = nil
                }
                trashed = true
            } catch {
                errors.append("Could not delete \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if trashed { rescanTree() }
        setFileOperationErrors(errors)
    }

    @discardableResult
    func receiveDrop(_ rawSources: [URL], into directory: URL) -> Bool {
        guard let vaultURL else { return false }
        let sources = VaultItem.topLevelURLs(rawSources.map {
            URL(filePath: VaultItem.path(of: $0))
        })
        var errors: [String] = []
        var relocations: [(old: URL, new: URL)] = []
        var destinations: [URL] = []

        for source in sources {
            let isInternal = Self.contains(source, in: vaultURL) && source != vaultURL
            let destination = isInternal
                ? VaultItem.moveDestination(for: source, into: directory, vaultURL: vaultURL)
                : VaultItem.importDestination(for: source, into: directory, vaultURL: vaultURL)
            guard let destination else {
                errors.append("Could not place \(source.lastPathComponent) there.")
                continue
            }
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
                errors.append("\(destination.lastPathComponent) already exists there.")
                continue
            }
            do {
                if isInternal {
                    try FileManager.default.moveItem(at: source, to: destination)
                    relocations.append((source, destination))
                } else {
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                destinations.append(destination)
            } catch {
                let verb = isInternal ? "move" : "copy"
                errors.append("Could not \(verb) \(source.lastPathComponent): \(error.localizedDescription)")
            }
        }

        for relocation in relocations {
            if let updated = Self.adjustURL(openDocument?.url, from: relocation.old, to: relocation.new) {
                openDocument?.relocate(to: updated)
            }
            if let updated = Self.adjustURL(activeFileURL, from: relocation.old, to: relocation.new) {
                activeFileURL = updated
            }
        }
        if !destinations.isEmpty {
            rescanTree()
            selectedItemURLs = Set(destinations)
        }
        setFileOperationErrors(errors)
        return !destinations.isEmpty
    }

    func dismissFileOpError() {
        fileOpErrorMessage = nil
    }

    private func setFileOperationErrors(_ errors: [String]) {
        switch errors.count {
        case 0:
            fileOpErrorMessage = nil
        case 1:
            fileOpErrorMessage = errors[0]
        default:
            fileOpErrorMessage = "\(errors.count) items could not be completed. \(errors[0])"
        }
    }

    func item(at url: URL) -> VaultItem? {
        func search(_ items: [VaultItem]) -> VaultItem? {
            for item in items {
                if item.url == url { return item }
                if let found = search(item.children ?? []) { return found }
            }
            return nil
        }
        return search(tree)
    }

    private func firstSelectedMarkdownURL(in items: [VaultItem]) -> URL? {
        for item in items {
            if item.isMarkdown, selectedItemURLs.contains(item.url) {
                return item.url
            }
            if let found = firstSelectedMarkdownURL(in: item.children ?? []) {
                return found
            }
        }
        return nil
    }

    private static func adjustURL(_ url: URL?, from oldURL: URL, to newURL: URL) -> URL? {
        guard let url else { return nil }
        let path = url.path(percentEncoded: false)
        let oldPath = oldURL.path(percentEncoded: false)
        if path == oldPath { return newURL }
        if path.hasPrefix(oldPath + "/") {
            return URL(filePath: newURL.path(percentEncoded: false) + path.dropFirst(oldPath.count))
        }
        return nil
    }

    private static func contains(_ url: URL?, in itemURL: URL) -> Bool {
        guard let url else { return false }
        let path = VaultItem.path(of: url)
        let itemPath = VaultItem.path(of: itemURL)
        return path == itemPath || path.hasPrefix(itemPath + "/")
    }

    private func saveOpenDocumentBeforeClosing() -> Bool {
        guard let openDocument else { return true }
        guard openDocument.save() else {
            activeFileURL = openDocument.url
            selectedItemURLs = [openDocument.url]
            return false
        }
        return true
    }

    private func availableURL(in parent: URL, baseName: String, fileExtension: String?) -> URL {
        let fileManager = FileManager.default
        for n in 1...1000 {
            let name = n == 1 ? baseName : "\(baseName) \(n)"
            let fullName = fileExtension.map { "\(name).\($0)" } ?? name
            let candidate = parent.appending(path: fullName).standardizedFileURL
            if !fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }
        let fallback = "\(baseName)-\(UUID().uuidString)" + (fileExtension.map { ".\($0)" } ?? "")
        return parent.appending(path: fallback)
    }
}
