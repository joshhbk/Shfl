import SwiftUI

extension EnvironmentValues {
    /// The launch's artwork store. `ShuffledApp` provides it for live
    /// launches; deterministic launches and previews leave it nil, so artwork
    /// views show placeholders.
    @Entry var artworkStore: ArtworkStore? = nil
}
