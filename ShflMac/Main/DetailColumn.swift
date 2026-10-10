import ShflCore
import SwiftUI

struct DetailColumn: View {
    let place: SidebarItem
    let isSearchFocused: FocusState<Bool>.Binding

    var body: some View {
        switch place {
        case .songs:
            LibrarySongsView()
                .navigationTitle("Songs")
                .placeSearch("Search Songs", isFocused: isSearchFocused)
        case .artists:
            ArtistsView()
                .placeSearch("Search Artists", isFocused: isSearchFocused)
        case .playlists:
            PlaylistsView()
                .placeSearch("Search Playlists", isFocused: isSearchFocused)
        case .selected:
            SelectedSongsView()
                .navigationTitle("Selected")
                .placeSearch("Search Selected", isFocused: isSearchFocused)
        case .upNext:
            UpNextView()
                .navigationTitle("Up Next")
        }
    }
}

private struct PlaceSearch: ViewModifier {
    let prompt: String
    let isFocused: FocusState<Bool>.Binding

    @Environment(LibraryBrowser.self) private var browser

    func body(content: Content) -> some View {
        @Bindable var browser = browser
        content
            .searchable(text: $browser.searchText, placement: .toolbar, prompt: prompt)
            .searchFocused(isFocused)
    }
}

private extension View {
    func placeSearch(_ prompt: String, isFocused: FocusState<Bool>.Binding) -> some View {
        modifier(PlaceSearch(prompt: prompt, isFocused: isFocused))
    }
}
