import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @Bindable var document: OpenDocument
    @AppStorage("editorFontSize") private var editorFontSize = 14.0

    var body: some View {
        TextEditor(text: $document.text, selection: $document.selection)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let conflict = document.conflict {
                    ConflictBannerView(
                        fileName: document.fileName,
                        conflict: conflict,
                        reload: { document.reloadFromDisk(fontSize: editorFontSize) },
                        keepMine: { document.keepMine() },
                        discard: { appState.discardOpenDocument() }
                    )
                } else if let message = document.saveErrorMessage {
                    InlineErrorBannerView(message: message) { document.dismissSaveError() }
                }
            }
            .safeAreaPadding(12)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: document.text) {
                let current = String(document.text.characters)
                guard current != document.plainText else { return }
                document.noteEdit(current)
            }
            .task(id: document.editGeneration) {
                guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
                document.restyle(fontSize: editorFontSize)
                guard (try? await Task.sleep(for: .milliseconds(850))) != nil else { return }
                guard document.conflict == nil else { return }
                document.save()
            }
            .onChange(of: editorFontSize) {
                document.restyle(fontSize: editorFontSize)
            }
    }
}
