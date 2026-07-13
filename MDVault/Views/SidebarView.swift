import SwiftUI

/// The vault file tree. Selection is by file URL; only markdown files are
/// selectable (folders disclose, other files are visible but inert).
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    /// Whether the sidebar column is collapsed to detail-only.
    let sidebarCollapsed: Bool

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.selectedFileURL) {
            OutlineGroup(appState.tree, children: \.children) { item in
                FileTreeRowView(item: item)
                    .selectionDisabled(!item.isMarkdown)
                    .contextMenu {
                        if item.isDirectory {
                            Button("New File") { appState.createFile(in: item.url) }
                            Button("New Folder") { appState.createFolder(in: item.url) }
                            Divider()
                        }
                        Button("Rename") { appState.renamingItemURL = item.url }
                        Button("Move to Trash", role: .destructive) { appState.trash(item.url) }
                    }
            }
        }
        .contextMenu {
            Button("New File") { appState.createFile(in: nil) }
            Button("New Folder") { appState.createFolder(in: nil) }
        }
        .onDeleteCommand {
            if let url = appState.selectedFileURL {
                appState.trash(url)
            }
        }
        .onKeyPress(.return) {
            // Finder-style: Return renames the selected file. Ancestor key
            // handlers run before the focused view, so while a rename field
            // is open this must .ignore for Return to reach its onSubmit.
            guard appState.renamingItemURL == nil, let url = appState.selectedFileURL else { return .ignored }
            appState.renamingItemURL = url
            return .handled
        }
        .dropDestination(for: URL.self) { urls, _ in
            // Drops on empty list area target the vault root.
            guard let root = appState.vaultURL else { return false }
            return appState.move(urls, into: root)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = appState.fileOpErrorMessage {
                InlineErrorBannerView(message: message) { appState.dismissFileOpError() }
            }
        }
        .toolbar {
            // In the sidebar header normally; while the sidebar is collapsed
            // its section overflows to a chevron at the window's far right,
            // so re-home the button beside the toggle instead.
            ToolbarItemGroup(placement: sidebarCollapsed ? .navigation : .primaryAction) {
                Button {
                    appState.newFileRelativeToSelection()
                } label: {
                    Label("New File", systemImage: "square.and.pencil")
                }
                .help("New file (⌘N)")
            }
        }
    }
}
