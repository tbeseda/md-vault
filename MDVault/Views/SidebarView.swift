import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    let sidebarCollapsed: Bool
    @Namespace private var dragNamespace

    var body: some View {
        @Bindable var appState = appState
        List(selection: $appState.selectedItemURLs) {
            OutlineGroup(appState.tree, children: \.children) { item in
                FileTreeRowView(item: item, dragNamespace: dragNamespace)
                    .tag(item.url)
            }
        }
        .onChange(of: appState.selectedItemURLs) {
            appState.selectionDidChange()
        }
        .dragContainer(for: URL.self, itemID: \.self, in: dragNamespace) { urls in urls }
        .dragContainerSelection(Array(appState.selectedItemURLs), containerNamespace: dragNamespace)
        .dragConfiguration(.init(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: true, allowMove: false)
        ))
        .contextMenu(forSelectionType: URL.self) { urls in
            if urls.isEmpty {
                Button("New File") { appState.createFile(in: nil) }
                Button("New Folder") { appState.createFolder(in: nil) }
            } else {
                if urls.count == 1,
                   let url = urls.first,
                   let item = appState.item(at: url),
                   item.isDirectory {
                    Button("New File") { appState.createFile(in: item.url) }
                    Button("New Folder") { appState.createFolder(in: item.url) }
                    Divider()
                }
                Button(urls.count == 1 ? "Copy Full Path" : "Copy Full Paths") {
                    appState.copyFullPaths(urls)
                }
                Button("Show in Finder") { appState.showInFinder(urls) }
                Divider()
                Button("Rename") { appState.beginRenaming(urls) }
                    .disabled(urls.count != 1)
                Button("Move to Trash", role: .destructive) {
                    appState.trash(Array(urls))
                }
            }
        } primaryAction: { urls in
            appState.beginRenaming(urls)
        }
        .onDeleteCommand {
            appState.trashSelection()
        }
        .onKeyPress(.return) {
            // Let Return reach the rename field when it is open.
            guard appState.renamingItemURL == nil,
                  appState.selectedItemURLs.count == 1,
                  let url = appState.selectedItemURLs.first
            else { return .ignored }
            appState.renamingItemURL = url
            return .handled
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let root = appState.vaultURL else { return false }
            return appState.receiveDrop(urls, into: root)
        }
        .dropConfiguration { session in
            .init(operation: session.localSession == nil ? .copy : .move)
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
