import AppKit
import ShflCore
import SwiftUI

struct MainSplitView: View {
    @State private var selection: SidebarItem? = .songs
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @SceneStorage("isShowingPlayer") private var isShowingPlayer = true
    @FocusState private var isSearchFocused: Bool
    @State private var scopedSearch: ScopedSearch?
    @Environment(LibraryBrowser.self) private var browser
    @Environment(ListeningSessionHost.self) private var sessionHost

    private var place: SidebarItem { selection ?? .songs }

    private var searchText: Binding<String> {
        if let scopedSearch {
            Binding(get: { scopedSearch.text }, set: { scopedSearch.text = $0 })
        } else {
            Binding(get: { browser.searchText }, set: { browser.searchText = $0 })
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            DetailColumn(place: place)
                .safeAreaInset(edge: .trailing, spacing: 0) { PicksColumn() }
                .environment(\.showPlace, ShowPlaceAction { selection = $0 })
                .environment(\.setSearchScope, SearchScopeAction { scopedSearch = $0 })
                .safeAreaInset(edge: .bottom, spacing: 0) { DraftFailureMessage() }
                .inspector(isPresented: $isShowingPlayer) {
                    PlayingColumn()
                        .inspectorColumnWidth(min: 320, ideal: 340, max: 420)
                        .toolbar {
                            Button("Player", systemImage: "sidebar.right") { isShowingPlayer.toggle() }
                                .help(isShowingPlayer ? "Hide Player" : "Show Player")
                        }
                }
        }
        // One for the window: per-place searchables can briefly coexist, and NSToolbar throws on a second.
        .searchable(text: searchText, placement: .toolbarPrincipal, prompt: scopedSearch?.prompt ?? place.searchPrompt)
        .searchFocused($isSearchFocused)
        .focusedSceneValue(\.isEditingText, isSearchFocused)
        .onKeyPress(.space, action: playPauseFromSpace)
        .onChange(of: selection, initial: true) {
            browser.activeLane = place.libraryLane
        }
    }

    // A menu key equivalent for Space would also take the spaces typed into text fields.
    private func playPauseFromSpace() -> KeyPress.Result {
        guard !isSearchFocused, !(NSApp.keyWindow?.firstResponder is NSText) else { return .ignored }
        Task { await sessionHost.togglePlayback() }
        return .handled
    }
}
