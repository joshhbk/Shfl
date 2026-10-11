import ShflCore
import SwiftUI

/// View › Sort Songs By, the keyboard route to the Songs column headers.
struct SortCommands: Commands {
    let browser: LibraryBrowser

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Picker("Sort Songs By", selection: browser.sortSelection) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
        }
    }
}
