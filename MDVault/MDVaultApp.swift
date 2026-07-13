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
            // Adds the standard Find and Spelling/Substitutions menus, which
            // SwiftUI's default Edit menu omits on macOS.
            TextEditingCommands()
            CommandGroup(replacing: .newItem) {
                Button("New File") { appState.newFileRelativeToSelection() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(appState.vaultURL == nil)
                Divider()
                Button("Open Vault…") { appState.chooseVault() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Close Vault") { appState.closeVault() }
                    .disabled(appState.vaultURL == nil)
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
