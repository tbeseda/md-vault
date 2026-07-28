import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
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
            // Let Return reach the rename field when it is open.
            guard appState.renamingItemURL == nil, let url = appState.selectedFileURL else { return .ignored }
            appState.renamingItemURL = url
            return .handled
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let root = appState.vaultURL else { return false }
            return appState.move(urls, into: root)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let message = appState.fileOpErrorMessage {
                InlineErrorBannerView(message: message) { appState.dismissFileOpError() }
            }
        }
        .toolbar {
            // Keep the action beside the sidebar toggle when collapsed.
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
