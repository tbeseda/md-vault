import AppKit
import SwiftUI

/// AppKit-backed vault file tree.
///
/// SwiftUI's `List` + `OutlineGroup` cannot own selection and row dragging at the
/// same time on macOS 26: `draggable(containerItemID:)` consumes clicks inside its
/// hit region, and the tap gestures needed to work around that become a second
/// writer to the selection set, so the two disagree under rapid clicking.
/// `NSOutlineView` resolves selection, dragging, and rename in one delegate.
struct FileTreeView: NSViewRepresentable {
    let appState: AppState
    let tree: [VaultItem]
    let selection: Set<URL>
    let renamingItemURL: URL?
    let fontSize: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let outlineView = FileTreeOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowHeight = 24
        outlineView.indentationPerLevel = 14
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.allowsColumnResizing = false
        outlineView.backgroundColor = .clear
        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator
        outlineView.target = coordinator
        outlineView.doubleAction = #selector(Coordinator.rowWasDoubleClicked(_:))
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.onDeleteKey = { [weak coordinator] in coordinator?.trashSelection() }
        outlineView.onReturnKey = { [weak coordinator] in coordinator?.renameSelection() }

        let menu = NSMenu()
        menu.delegate = coordinator
        outlineView.menu = menu

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = true

        coordinator.outlineView = outlineView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let outlineView = scrollView.documentView as? FileTreeOutlineView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyTree(tree, to: outlineView)
        coordinator.syncSelection(selection, in: outlineView)
        coordinator.syncRenaming(renamingItemURL, in: outlineView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate,
                             NSTextFieldDelegate, NSMenuDelegate {
        var parent: FileTreeView
        weak var outlineView: FileTreeOutlineView?

        /// Nodes are cached by normalized path so the same object represents a
        /// given item across reloads. `NSOutlineView` keys expansion state on item
        /// identity, so reusing them is what keeps folders open across a rescan.
        private var nodes: [String: FileTreeNode] = [:]
        private var roots: [FileTreeNode] = []
        private var appliedTree: [VaultItem] = []
        private var isSyncingSelection = false
        private var editingURL: URL?
        private var draggedURLs: [URL] = []

        init(parent: FileTreeView) {
            self.parent = parent
        }

        private var appState: AppState { parent.appState }

        // MARK: Tree

        func applyTree(_ tree: [VaultItem], to outlineView: NSOutlineView) {
            guard tree != appliedTree else { return }
            appliedTree = tree

            let expanded = expandedPaths(in: outlineView)
            var rebuilt: [String: FileTreeNode] = [:]
            roots = makeNodes(tree, into: &rebuilt)
            nodes = rebuilt
            outlineView.reloadData()
            restoreExpansion(expanded, in: outlineView)
        }

        private func makeNodes(_ items: [VaultItem], into cache: inout [String: FileTreeNode]) -> [FileTreeNode] {
            items.map { item in
                let path = VaultItem.path(of: item.url)
                let node = nodes[path] ?? FileTreeNode(item: item)
                node.item = item
                node.children = item.children.map { makeNodes($0, into: &cache) }
                cache[path] = node
                return node
            }
        }

        private func expandedPaths(in outlineView: NSOutlineView) -> Set<String> {
            var paths: Set<String> = []
            for row in 0..<outlineView.numberOfRows {
                guard let node = outlineView.item(atRow: row) as? FileTreeNode,
                      outlineView.isItemExpanded(node) else { continue }
                paths.insert(VaultItem.path(of: node.url))
            }
            return paths
        }

        private func restoreExpansion(_ paths: Set<String>, in outlineView: NSOutlineView) {
            func walk(_ nodes: [FileTreeNode]) {
                for node in nodes {
                    guard paths.contains(VaultItem.path(of: node.url)) else { continue }
                    outlineView.expandItem(node)
                    walk(node.children ?? [])
                }
            }
            walk(roots)
        }

        private func node(for url: URL) -> FileTreeNode? {
            nodes[VaultItem.path(of: url)]
        }

        /// Expands every folder above `path` so the row exists and can be selected.
        private func expandAncestors(ofPath path: String, in outlineView: NSOutlineView) {
            var chain: [FileTreeNode] = []
            var current = (path as NSString).deletingLastPathComponent
            while current.count > 1, let node = nodes[current] {
                chain.append(node)
                current = (current as NSString).deletingLastPathComponent
            }
            for node in chain.reversed() {
                outlineView.expandItem(node)
            }
        }

        // MARK: Selection

        func syncSelection(_ selection: Set<URL>, in outlineView: NSOutlineView) {
            for url in selection {
                expandAncestors(ofPath: VaultItem.path(of: url), in: outlineView)
            }
            let rows = selection.compactMap { url -> Int? in
                guard let node = node(for: url) else { return nil }
                let row = outlineView.row(forItem: node)
                return row >= 0 ? row : nil
            }
            let indexes = IndexSet(rows)
            guard indexes != outlineView.selectedRowIndexes else { return }
            isSyncingSelection = true
            outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
            isSyncingSelection = false
            if let first = indexes.first {
                outlineView.scrollRowToVisible(first)
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                  let outlineView = notification.object as? NSOutlineView else { return }
            let urls = Set(outlineView.selectedRowIndexes.compactMap {
                (outlineView.item(atRow: $0) as? FileTreeNode)?.url
            })
            guard urls != appState.selectedItemURLs else { return }
            appState.selectedItemURLs = urls
            appState.selectionDidChange(fontSize: parent.fontSize)
            // A blocked save restores the conflicted document's selection; settle
            // the view against the model before the next click is processed.
            syncSelection(appState.selectedItemURLs, in: outlineView)
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? FileTreeNode)?.children?.isEmpty == false
        }

        private func children(of item: Any?) -> [FileTreeNode] {
            guard let node = item as? FileTreeNode else { return roots }
            return node.children ?? []
        }

        // MARK: Rows

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? FileTreeNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("FileTreeCell")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? FileTreeCellView
                ?? FileTreeCellView(identifier: identifier)
            cell.configure(with: node.item)
            cell.textField?.delegate = self
            return cell
        }

        // MARK: Rename

        func syncRenaming(_ url: URL?, in outlineView: NSOutlineView) {
            if let url {
                guard url != editingURL else { return }
                beginEditing(url, in: outlineView)
            } else if editingURL != nil {
                outlineView.window?.makeFirstResponder(outlineView)
            }
        }

        private func beginEditing(_ url: URL, in outlineView: NSOutlineView) {
            guard let node = node(for: url) else { return }
            let row = outlineView.row(forItem: node)
            guard row >= 0,
                  let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileTreeCellView,
                  let field = cell.textField else { return }
            editingURL = url
            field.isEditable = true
            outlineView.editColumn(0, row: row, with: nil, select: true)
            // Finder-style: preselect the base name and leave the extension alone.
            guard !node.item.isDirectory,
                  let editor = outlineView.window?.fieldEditor(false, for: field) as? NSTextView else { return }
            let name = field.stringValue as NSString
            let extensionLength = name.pathExtension.count
            guard extensionLength > 0, extensionLength + 1 < name.length else { return }
            editor.setSelectedRange(NSRange(location: 0, length: name.length - extensionLength - 1))
        }

        /// Escape aborts the table's field editor without posting the end-editing
        /// notification, so cancelling has to be intercepted here or the cell is
        /// left permanently editable.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)),
                  let field = control as? NSTextField else { return false }
            let url = editingURL
            editingURL = nil
            field.abortEditing()
            field.isEditable = false
            appState.renamingItemURL = nil
            if let url, let item = appState.item(at: url) {
                field.stringValue = item.name
            }
            outlineView?.window?.makeFirstResponder(outlineView)
            return true
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            field.isEditable = false
            guard let url = editingURL else { return }
            editingURL = nil
            appState.renamingItemURL = nil
            guard let item = appState.item(at: url) else { return }

            let movement = notification.userInfo?["NSTextMovement"] as? Int
            guard movement != NSTextMovement.cancel.rawValue else {
                field.stringValue = item.name
                return
            }
            appState.rename(item, to: field.stringValue)
            if appState.item(at: url) != nil {
                // The rename was rejected or a no-op, so the row still shows the
                // old item and the tree will not reload to correct the field.
                field.stringValue = item.name
            }
        }

        func renameSelection() {
            appState.beginRenaming(appState.selectedItemURLs)
        }

        func trashSelection() {
            appState.trashSelection()
        }

        @objc func rowWasDoubleClicked(_ sender: Any?) {
            guard let outlineView, outlineView.clickedRow >= 0 else { return }
            renameSelection()
        }

        // MARK: Drag and drop

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            (item as? FileTreeNode).map { $0.url as NSURL }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forItems draggedItems: [Any]
        ) {
            draggedURLs = draggedItems.compactMap { ($0 as? FileTreeNode)?.url }
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            draggedURLs = []
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            validateDrop info: NSDraggingInfo,
            proposedItem item: Any?,
            proposedChildIndex index: Int
        ) -> NSDragOperation {
            guard let directory = dropDirectory(for: item) else { return [] }
            let isLocal = (info.draggingSource as? NSOutlineView) === outlineView
            if isLocal, !canMove(draggedURLs, into: directory) { return [] }
            // Always drop onto a container, never between rows.
            outlineView.setDropItem(dropNode(for: item), dropChildIndex: NSOutlineViewDropOnItemIndex)
            return isLocal ? .move : .copy
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            acceptDrop info: NSDraggingInfo,
            item: Any?,
            childIndex index: Int
        ) -> Bool {
            guard let directory = dropDirectory(for: item),
                  let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
                  !urls.isEmpty else { return false }
            return appState.receiveDrop(urls, into: directory)
        }

        /// A file row targets its enclosing folder; everything else targets the vault root.
        private func dropNode(for item: Any?) -> FileTreeNode? {
            guard let node = item as? FileTreeNode else { return nil }
            if node.item.isDirectory { return node }
            return self.node(for: node.url.deletingLastPathComponent())
        }

        private func dropDirectory(for item: Any?) -> URL? {
            guard let node = item as? FileTreeNode else { return appState.vaultURL }
            return node.item.isDirectory ? node.url : node.url.deletingLastPathComponent()
        }

        /// Mirrors `VaultItem.moveDestination`, so a rejected move shows no drop cursor
        /// instead of failing with an error banner after the drop.
        private func canMove(_ sources: [URL], into directory: URL) -> Bool {
            guard !sources.isEmpty else { return false }
            let directoryPath = VaultItem.path(of: directory)
            return sources.allSatisfy { source in
                let sourcePath = VaultItem.path(of: source)
                return directoryPath != sourcePath
                    && !directoryPath.hasPrefix(sourcePath + "/")
                    && directoryPath != VaultItem.path(of: source.deletingLastPathComponent())
            }
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }
            let clickedRow = outlineView.clickedRow
            if clickedRow >= 0, !outlineView.selectedRowIndexes.contains(clickedRow) {
                // Right-clicking outside the selection targets just that row.
                outlineView.selectRowIndexes([clickedRow], byExtendingSelection: false)
            }

            guard clickedRow >= 0 else {
                menu.addItem(menuItem("New File") { [self] in appState.createFile(in: nil) })
                menu.addItem(menuItem("New Folder") { [self] in appState.createFolder(in: nil) })
                return
            }

            let urls = appState.selectedItemURLs
            if urls.count == 1, let url = urls.first, appState.item(at: url)?.isDirectory == true {
                menu.addItem(menuItem("New File") { [self] in appState.createFile(in: url) })
                menu.addItem(menuItem("New Folder") { [self] in appState.createFolder(in: url) })
                menu.addItem(.separator())
            }
            menu.addItem(menuItem(urls.count == 1 ? "Copy Full Path" : "Copy Full Paths") { [self] in
                appState.copyFullPaths(urls)
            })
            menu.addItem(menuItem("Show in Finder") { [self] in appState.showInFinder(urls) })
            menu.addItem(.separator())
            let rename = menuItem("Rename") { [self] in appState.beginRenaming(urls) }
            rename.isEnabled = urls.count == 1
            menu.addItem(rename)
            menu.addItem(menuItem("Move to Trash") { [self] in appState.trash(Array(urls)) })
        }

        private func menuItem(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuAction(handler)
            return item
        }

        @objc private func runMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? MenuAction)?.handler()
        }

        private final class MenuAction: NSObject {
            let handler: @MainActor () -> Void
            init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
        }
    }
}

// MARK: - Node

/// Reference identity is what `NSOutlineView` uses to map items to rows, so the
/// value-type `VaultItem` is wrapped rather than used directly.
final class FileTreeNode: NSObject {
    let url: URL
    var item: VaultItem
    var children: [FileTreeNode]?

    init(item: VaultItem) {
        url = item.url
        self.item = item
    }
}

// MARK: - Outline view

final class FileTreeOutlineView: NSOutlineView {
    var onDeleteKey: (() -> Void)?
    var onReturnKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isEmpty, let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else {
            super.keyDown(with: event)
            return
        }
        switch Int(scalar.value) {
        case NSDeleteCharacter, NSDeleteFunctionKey:
            onDeleteKey?()
        case NSCarriageReturnCharacter, NSEnterCharacter:
            onReturnKey?()
        default:
            // Falls through so type-select still works.
            super.keyDown(with: event)
        }
    }
}

// MARK: - Cell

final class FileTreeCellView: NSTableCellView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.setContentHuggingPriority(.required, for: .horizontal)
        name.isEditable = false
        name.isBordered = false
        name.drawsBackground = false
        name.lineBreakMode = .byTruncatingMiddle
        name.cell?.usesSingleLineMode = true

        let stack = NSStackView(views: [icon, name])
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        imageView = icon
        textField = name
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FileTreeCellView is not loaded from a nib") }

    func configure(with item: VaultItem) {
        let isPrimary = item.isDirectory || item.isMarkdown
        icon.image = NSImage(systemSymbolName: symbolName(for: item), accessibilityDescription: nil)
        icon.contentTintColor = isPrimary ? .secondaryLabelColor : .tertiaryLabelColor
        name.stringValue = item.name
        name.textColor = isPrimary ? .labelColor : .tertiaryLabelColor
        name.isEditable = false
    }

    private func symbolName(for item: VaultItem) -> String {
        if item.isDirectory {
            "folder"
        } else if item.isMarkdown {
            "doc.text"
        } else {
            "doc"
        }
    }
}
