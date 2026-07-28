import SwiftUI

@MainActor @Observable
final class AppState {
    private(set) var vaultURL: URL?
    private(set) var tree: [VaultItem] = []
    var selectedFileURL: URL?
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
        selectedFileURL = nil
        openDocument = nil
        openError = nil
        rescanTree()
    }

    func closeVault() {
        guard saveOpenDocumentBeforeClosing() else { return }
        defaults.removeObject(forKey: "vaultPath")
        vaultURL = nil
        tree = []
        selectedFileURL = nil
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
        if let selectedFileURL, !contains(selectedFileURL) {
            if let openDocument, openDocument.isDirty {
                openDocument.conflict = .deleted
            } else {
                self.selectedFileURL = nil
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

    func openSelectedFile(fontSize: CGFloat) {
        guard let url = selectedFileURL else {
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

    func discardOpenDocument() {
        selectedFileURL = nil
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
        createFile(in: selectedFileURL?.deletingLastPathComponent())
    }

    func createFile(in directory: URL?) {
        guard let parent = directory ?? vaultURL else { return }
        guard saveOpenDocumentBeforeClosing() else { return }
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
            if let updated = Self.adjustURL(selectedFileURL, from: item.url, to: destination) {
                selectedFileURL = updated
            }
            rescanTree()
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not rename \(item.name): \(error.localizedDescription)"
        }
    }

    func trash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if Self.contains(openDocument?.url, in: url) {
                selectedFileURL = nil
                openDocument = nil
                openError = nil
            }
            rescanTree()
            fileOpErrorMessage = nil
        } catch {
            fileOpErrorMessage = "Could not delete \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

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

    func dismissFileOpError() {
        fileOpErrorMessage = nil
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
        let path = url.path(percentEncoded: false)
        let itemPath = itemURL.path(percentEncoded: false)
        return path == itemPath || path.hasPrefix(itemPath + "/")
    }

    private func saveOpenDocumentBeforeClosing() -> Bool {
        guard let openDocument else { return true }
        guard openDocument.save() else {
            selectedFileURL = openDocument.url
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
