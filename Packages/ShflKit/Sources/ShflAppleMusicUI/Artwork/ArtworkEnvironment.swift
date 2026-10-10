import ShflAppleMusic
import SwiftUI

extension EnvironmentValues {
    /// The launch's artwork store. The shell provides it for live launches;
    /// deterministic launches and previews leave it nil, so artwork views
    /// show placeholders.
    @Entry public var artworkStore: ArtworkStore? = nil
}
