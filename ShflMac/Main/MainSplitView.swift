import AppKit
import ShflCore
import SwiftUI

struct MainSplitView: View {
    @State private var selection: SidebarItem? = .songs
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @SceneStorage("isShowingPlayer") private var isShowingPlayer = true
    @FocusState private var isSearchFocused: Bool
    @Environment(LibraryBrowser.self) private var browser
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
        } detail: {
            DetailColumn(place: selection ?? .songs, isSearchFocused: $isSearchFocused)
                .environment(\.showPlace, ShowPlaceAction { selection = $0 })
                .safeAreaInset(edge: .bottom, spacing: 0) { DraftFailureMessage() }
                .toolbar { LibraryToolbar() }
                .inspector(isPresented: $isShowingPlayer) {
                    PlayingColumn()
                        .inspectorColumnWidth(min: 320, ideal: 340, max: 420)
                        .toolbar {
                            Button("Player", systemImage: "sidebar.right") { isShowingPlayer.toggle() }
                                .help(isShowingPlayer ? "Hide Player" : "Show Player")
                        }
                }
        }
        .focusedSceneValue(\.isEditingText, isSearchFocused)
        .onKeyPress(.space, action: playPauseFromSpace)
        .onChange(of: selection, initial: true) {
            browser.activeLane = (selection ?? .songs).libraryLane
        }
    }

    // A menu key equivalent for Space would also take the spaces typed into text fields.
    private func playPauseFromSpace() -> KeyPress.Result {
        guard !isSearchFocused, !(NSApp.keyWindow?.firstResponder is NSText) else { return .ignored }
        Task { await sessionHost.togglePlayback() }
        return .handled
    }
}
