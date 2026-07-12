import SwiftUI

@main
struct MDVaultApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
        .defaultSize(width: 1100, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") { appState.newFileRelativeToSelection() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(appState.vaultURL == nil)
                Divider()
                Button("Open Vault…") { appState.chooseVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                Button("Move to Trash") {
                    if let url = appState.selectedFileURL { appState.trash(url) }
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.selectedFileURL == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { appState.openDocument?.saveCommand() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(appState.openDocument == nil)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
