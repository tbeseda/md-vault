import SwiftUI

struct SettingsView: View {
    @AppStorage("editorFontSize") private var editorFontSize = 14.0

    var body: some View {
        Form {
            Section("Editor") {
                Stepper("Font Size: \(Int(editorFontSize)) pt", value: $editorFontSize, in: 10...24, step: 1)
            }
        }
        .formStyle(.grouped)
        .frame(width: 350)
        .fixedSize()
    }
}
