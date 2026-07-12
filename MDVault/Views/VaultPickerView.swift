import SwiftUI

/// Welcome screen shown until a vault is open.
struct VaultPickerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ContentUnavailableView {
            Label("md-vault", systemImage: "books.vertical")
        } description: {
            Text("Open a folder of markdown files, or create an empty folder to start a new vault.")
        } actions: {
            Button("Open Vault…") { appState.chooseVault() }
                .buttonStyle(.borderedProminent)
        }
    }
}
