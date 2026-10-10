import ShflCore
import SwiftUI

struct LibrarySettingsTab: View {
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        Form {
            SongSortPicker(selection: browser.sortSelection)
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("mac.settings.sort")
        }
        .formStyle(.grouped)
    }
}
