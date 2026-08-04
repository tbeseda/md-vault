import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("editorFontSize") private var editorFontSize = 14.0
    let sidebarCollapsed: Bool

    var body: some View {
        FileTreeView(
            appState: appState,
            tree: appState.tree,
            selection: appState.selectedItemURLs,
            renamingItemURL: appState.renamingItemURL,
            fontSize: editorFontSize
        )
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
