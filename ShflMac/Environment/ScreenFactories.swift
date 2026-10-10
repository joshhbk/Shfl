import ShflComposition
import ShflCore
import SwiftUI

// A struct around the model rather than closures, so the environment can tell it hasn't changed.
struct ScreenFactories {
    fileprivate let model: AppModel?

    @MainActor
    func makePlaybackClock() -> PlaybackClock {
        injectedModel.makePlaybackClock()
    }

    @MainActor
    func makeSongs(by artist: Artist) -> ArtistDetailViewModel {
        injectedModel.makeSongs(by: artist)
    }

    @MainActor
    func makeSongs(in playlist: Playlist) -> PlaylistDetailViewModel {
        injectedModel.makeSongs(in: playlist)
    }

    private var injectedModel: AppModel {
        guard let model else {
            fatalError("ScreenFactories isn't in the environment; apply shellEnvironment(_:) above this view.")
        }
        return model
    }
}

extension ScreenFactories {
    init(model: AppModel) {
        self.model = model
    }
}

extension EnvironmentValues {
    @Entry var screenFactories = ScreenFactories(model: nil)
}
