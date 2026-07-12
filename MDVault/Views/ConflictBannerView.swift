import SwiftUI

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
