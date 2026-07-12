import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("editorFontSize") private var editorFontSize = 14.0

    var body: some View {
        if appState.vaultURL == nil {
            VaultPickerView()
        } else {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            } detail: {
                if let document = appState.openDocument {
                    EditorView(document: document)
                        .navigationTitle(document.fileName)
                        .navigationSubtitle(document.isDirty ? "Edited" : "")
                } else if let error = appState.openError {
                    ContentUnavailableView("Cannot Open File", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ContentUnavailableView("No File Selected", systemImage: "doc.text", description: Text("Choose a markdown file from the sidebar."))
                }
            }
            .onChange(of: appState.selectedFileURL) {
                appState.openSelectedFile(fontSize: editorFontSize)
            }
            .task(id: appState.vaultURL) {
                // Watch the vault for external changes (agents, editors).
                // The watcher lives and dies with this task; switching vaults
                // restarts it via the id.
                guard let vaultURL = appState.vaultURL else { return }
                let watcher = VaultWatcher(vaultURL: vaultURL)
                defer { watcher.stop() }
                for await _ in watcher.events {
                    appState.handleExternalChanges(fontSize: editorFontSize)
                }
            }
        }
    }
}
