import SwiftUI

/// Generic view that eliminates duplicate switch statements on PlaybackState
/// by providing loading/active/empty ViewBuilder slots
struct PlaybackStateContent<Loading: View, Active: View, Empty: View>: View {
    let playbackState: PlaybackState
    @ViewBuilder let loading: (Song) -> Loading
    @ViewBuilder let active: (Song) -> Active
    @ViewBuilder let empty: () -> Empty

    var body: some View {
        switch playbackState {
        case .loading(let song):
            loading(song)
                .transition(.opacity)
        case .playing(let song), .paused(let song):
            active(song)
                .transition(.opacity)
        case .empty, .stopped, .error:
            empty()
                .transition(.opacity)
        }
    }
}
