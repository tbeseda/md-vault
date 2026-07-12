import SwiftUI

struct FileTreeRowView: View {
    @Environment(AppState.self) private var appState
    let item: VaultItem
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        if appState.renamingItemURL == item.url {
            TextField("Name", text: $draftName)
                .focused($nameFieldFocused)
                .onAppear {
                    draftName = item.name
                    nameFieldFocused = true
                }
                .onSubmit { appState.rename(item, to: draftName) }
                .onExitCommand { appState.renamingItemURL = nil }
                .onChange(of: nameFieldFocused) {
                    // Losing focus without submitting cancels, like Escape.
                    if !nameFieldFocused, appState.renamingItemURL == item.url {
                        appState.renamingItemURL = nil
                    }
                }
        } else {
            Label(item.name, systemImage: icon)
                .foregroundStyle(item.isDirectory || item.isMarkdown ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
    }

    private var icon: String {
        if item.isDirectory {
            "folder"
        } else if item.isMarkdown {
            "doc.text"
        } else {
            "doc"
        }
    }
}
