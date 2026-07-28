import SwiftUI

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

struct ConflictBannerView: View {
    let fileName: String
    let conflict: OpenDocument.Conflict
    let reload: () -> Void
    let keepMine: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill")
            Spacer()
            if conflict == .deleted {
                Button("Close", action: discard)
                Button("Recreate", action: keepMine)
            } else {
                Button("Reload", action: reload)
                Button("Keep Mine", action: keepMine)
            }
        }
        .padding(8)
        .background(.bar)
    }

    private var message: String {
        switch conflict {
        case .modified: "\(fileName) changed on disk"
        case .deleted: "\(fileName) was deleted"
        }
    }
}
