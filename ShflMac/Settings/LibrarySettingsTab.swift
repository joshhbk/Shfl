import SwiftUI

struct LibrarySettingsTab: View {
    var body: some View {
        Form {
            SongSortPicker()
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("mac.settings.sort")
        }
        .formStyle(.grouped)
    }
}
