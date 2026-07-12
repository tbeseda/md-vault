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
                    }
            }
        }
        .contextMenu {
            Button("New File") { appState.createFile(in: nil) }
            Button("New Folder") { appState.createFolder(in: nil) }
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
