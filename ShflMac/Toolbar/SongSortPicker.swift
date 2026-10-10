import ShflCore
import SwiftUI

struct SongSortPicker: View {
    let selection: Binding<SortOption>

    var body: some View {
        Picker("Sort Songs By", selection: selection) {
            ForEach(SortOption.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
    }
}

extension LibraryBrowser {
    var sortSelection: Binding<SortOption> {
        Binding(get: { self.sortOption }, set: { self.chooseSortOption($0) })
    }
}
