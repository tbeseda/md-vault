import SwiftUI

/// The one shape for transient error messages (file ops, save failures):
/// an inline bar with a dismiss button, shown via safeAreaInset.
struct InlineErrorBannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
            Spacer()
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(8)
        .background(.bar)
    }
}

/// Shown when the open file changed on disk under unsaved edits.
struct ConflictBannerView: View {
    let fileName: String
    let reload: () -> Void
    let keepMine: () -> Void

    var body: some View {
        HStack {
            Label("\(fileName) changed on disk", systemImage: "exclamationmark.triangle.fill")
            Spacer()
            Button("Reload", action: reload)
            Button("Keep Mine", action: keepMine)
        }
        .padding(8)
        .background(.bar)
    }
}
