import ShflComposition
import SwiftUI

struct LaunchRootView: View {
    let model: AppModel

    var body: some View {
        content
            .frame(minWidth: 820, minHeight: 520)
            .task {
                // Reopening the window must not restore the session again.
                guard model.launchPhase == .loading else { return }
                await model.launch()
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
                makeArtistSongs: model.makeSongs(by:),
                makePlaylistSongs: model.makeSongs(in:)
            )
        }
    }
}
