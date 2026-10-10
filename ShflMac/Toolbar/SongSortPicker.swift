import ShflCore
import SwiftUI

struct SongSortPicker: View {
    @Environment(LibraryBrowser.self) private var browser

    var body: some View {
        Picker(
            "Sort Songs By",
            selection: Binding(get: { browser.sortOption }, set: browser.chooseSortOption)
        ) {
            ForEach(SortOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
    }
}
