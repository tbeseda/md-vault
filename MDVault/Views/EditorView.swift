import SwiftUI

/// The markdown editor pane: a plain SwiftUI TextEditor over a styled
/// AttributedString, restyled on a short debounce after each real edit and
/// autosaved once the edit settles.
struct EditorView: View {
    @Bindable var document: OpenDocument
    @AppStorage("editorFontSize") private var editorFontSize = 14.0

    var body: some View {
        TextEditor(text: $document.text, selection: $document.selection)
            .safeAreaInset(edge: .top, spacing: 0) {
                if document.conflict {
                    ConflictBannerView(
                        fileName: document.fileName,
                        reload: { document.reloadFromDisk(fontSize: editorFontSize) },
                        keepMine: { document.keepMine() }
                    )
                } else if let message = document.saveErrorMessage {
                    InlineErrorBannerView(message: message) { document.dismissSaveError() }
                }
            }
            .safeAreaPadding(12)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .onChange(of: document.text) {
                // Attribute-only changes (our own restyle) leave the character
                // content identical to plainText; only real edits pass.
                let current = String(document.text.characters)
                guard current != document.plainText else { return }
                document.noteEdit(current)
            }
            .task(id: document.editGeneration) {
                // Stage 1: restyle after a 150 ms pause in typing. Typed
                // characters inherit neighboring attributes in the meantime.
                guard (try? await Task.sleep(for: .milliseconds(150))) != nil else { return }
                document.restyle(fontSize: editorFontSize)
                // Stage 2: autosave once the edit is 1 s old. A fresh edit
                // cancels both stages; a conflict suspends autosave.
                guard (try? await Task.sleep(for: .milliseconds(850))) != nil else { return }
                guard !document.conflict else { return }
                document.save()
            }
            .onChange(of: editorFontSize) {
                document.restyle(fontSize: editorFontSize)
            }
    }
}
