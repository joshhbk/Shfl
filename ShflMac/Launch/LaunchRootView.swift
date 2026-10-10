import ShflComposition
import SwiftUI

struct LaunchRootView: View {
    let model: AppModel

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .frame(minWidth: 820, minHeight: 520)
            .task {
                // Reopening the window must not restore the session again.
                guard model.launchPhase == .loading else { return }
                await model.launch()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if oldPhase == .active && newPhase != .active {
                    model.sceneDidLeaveForeground()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.launchPhase {
        case .loading:
            ProgressView("Loading…")
        case .needsAuthorization:
            AuthorizationNeededView(requestAccess: model.requestAuthorization)
        case .authorizationDenied:
            AuthorizationDeniedView()
        case .ready:
            MainSplitView(
                makePlaybackClock: model.makePlaybackClock,
                makeArtistSongs: model.makeSongs(by:),
                makePlaylistSongs: model.makeSongs(in:)
            )
        }
    }
}
