import SwiftUI

/// Single source of truth for the app: the open vault, its file tree, and the open document.
@MainActor @Observable
final class AppState {
    private(set) var vaultURL: URL?
    private(set) var tree: [VaultItem] = []
    var selectedFileURL: URL?
    private(set) var openDocument: OpenDocument?
    private(set) var openError: String?
    var renamingItemURL: URL?
    private(set) var fileOpErrorMessage: String?

    init() {
        if let path = UserDefaults.standard.string(forKey: "vaultPath") {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                openVault(at: URL(filePath: path, directoryHint: .isDirectory))
            }
        }
        // SwiftUI has no reliable scene-teardown hook on macOS; flush the
        // buffer on quit via AppKit's notification (sanctioned escape hatch).
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.openDocument?.save()
            }
        }
    }

    // MARK: - Vault

    /// Present the vault chooser. NSOpenPanel is a sanctioned escape hatch:
    /// fileImporter cannot guarantee directory creation, and creating a new
    /// vault folder from the panel is a core flow.
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
        openDocument?.save()
        vaultURL = url.standardizedFileURL
        UserDefaults.standard.set(url.path(percentEncoded: false), forKey: "vaultPath")
        selectedFileURL = nil
        openDocument = nil
        openError = nil
        rescanTree()
    }

    /// Rebuild the whole tree from disk. The single code path for every
    /// mutation, local or external; vaults are small and rescans are cheap.
    func rescanTree() {
        guard let vaultURL else {
            tree = []
            return
        }
        tree = VaultItem.buildTree(at: vaultURL)
        if let selectedFileURL, !contains(selectedFileURL) {
            self.selectedFileURL = nil
            openDocument = nil
        }
    }

    private func contains(_ url: URL) -> Bool {
        func search(_ items: [VaultItem]) -> Bool {
            items.contains { $0.url == url || search($0.children ?? []) }
        }
        return search(tree)
    }

    // MARK: - Document

    func openSelectedFile(fontSize: CGFloat) {
        guard let url = selectedFileURL else {
            openDocument?.save()
            openDocument = nil
            openError = nil
            return
        }
        guard url != openDocument?.url else { return }
        openDocument?.save()
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            openDocument = OpenDocument(url: url, source: source, fontSize: fontSize)
            openError = nil
        } catch {
            openDocument = nil
            openError = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - External changes

    /// Handle a batch of FSEvents. The tree rescan is idempotent, so our own
    /// saves need no suppression there; for the open document, echo
    /// suppression is content comparison in `ExternalChange.determine`.
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
            document.conflict = true
        }
    }

    // MARK: - File operations

    func newFileRelativeToSelection() {
        createFile(in: selectedFileURL?.deletingLastPathComponent())
    }

    /// Create a deduped Untitled.md, select it, and enter rename mode.
    func createFile(in directory: URL?) {
        guard let parent = directory ?? vaultURL else { return }
        let url = availableURL(in: parent, baseName: "Untitled", fileExtension: "md")
        do {
            try Data().write(to: url)
            rescanTree()
            selectedFileURL = url
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
            renamingItemURL = url
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not create folder: \(error.localizedDescription)"
        }
    }

    func rename(_ item: VaultItem, to newName: String) {
        defer { renamingItemURL = nil }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let updated = Self.adjustURL(selectedFileURL, from: item.url, to: destination) {
                selectedFileURL = updated
            }
            rescanTree()
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not rename \(item.name): \(error.localizedDescription)"
        }
    }

    /// Move a file or folder to the Trash. Recoverable via Finder, so no
    /// confirmation, matching Finder's own behavior. If the open document was
    /// the item or inside it, the rescan drops it (same path as an external
    /// delete), which also cancels any pending autosave that would otherwise
    /// re-create the file.
    func trash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            rescanTree()
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not delete \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    /// Move dragged items into a folder. Drops that would be no-ops or leave
    /// the vault are ignored by the planner; name collisions surface as errors.
    @discardableResult
    func move(_ sources: [URL], into directory: URL) -> Bool {
        guard let vaultURL else { return false }
        fileOpErrorMessage = nil
        var moved = false
        for rawSource in sources {
            let source = URL(filePath: VaultItem.path(of: rawSource))
            guard let destination = VaultItem.moveDestination(for: source, into: directory, vaultURL: vaultURL) else { continue }
            guard !FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) else {
                fileOpErrorMessage = "\(destination.lastPathComponent) already exists there."
                continue
            }
            do {
                try FileManager.default.moveItem(at: source, to: destination)
                if let updated = Self.adjustURL(openDocument?.url, from: source, to: destination) {
                    openDocument?.relocate(to: updated)
                }
                if let updated = Self.adjustURL(selectedFileURL, from: source, to: destination) {
                    selectedFileURL = updated
                }
                moved = true
            } catch {
                fileOpErrorMessage = "Could not move \(source.lastPathComponent): \(error.localizedDescription)"
            }
        }
        if moved { rescanTree() }
        return moved
    }

    /// Map a URL affected by a move (the item itself or a descendant) to its
    /// new location; nil if unaffected.
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
