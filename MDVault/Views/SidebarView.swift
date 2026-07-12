import SwiftUI

/// The vault file tree. Selection is by file URL; only markdown files are
/// selectable (folders disclose, other files are visible but inert).
struct SidebarView: View {
    @Environment(AppState.self) private var appState

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
        .dropDestination(for: URL.self) { urls, _ in
            // Drops on empty list area target the vault root.
            guard let root = appState.vaultURL else { return false }
            return appState.move(urls, into: root)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = appState.fileOpErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
