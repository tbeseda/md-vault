import SwiftUI

struct FileTreeRowView: View {
    @Environment(AppState.self) private var appState
    let item: VaultItem
    @State private var draftName = ""
    @State private var isDropTargeted = false
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .draggable(item.url)
                .dropDestination(for: URL.self) { urls, _ in
                    // A drop on a folder moves into it; a drop on a file
                    // moves to the file's level, like Finder's list view.
                    appState.move(urls, into: item.isDirectory ? item.url : item.url.deletingLastPathComponent())
                } isTargeted: { targeted in
                    isDropTargeted = targeted && item.isDirectory
                }
                .background(.tint.opacity(isDropTargeted ? 0.2 : 0), in: RoundedRectangle(cornerRadius: 4))
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
