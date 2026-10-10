import MusicKit
import ShflAppleMusic
import ShflCore
import SwiftUI

/// Draws a library item's artwork at `size` points square, showing
/// `placeholder` until (or unless) the artwork store finds some.
public struct ArtworkView<Placeholder: View>: View {
    let subject: ArtworkSubject
    let size: CGFloat
    let placeholder: Placeholder

    @Environment(\.artworkStore) private var store
    @State private var artwork: Artwork?

    public init(subject: ArtworkSubject, size: CGFloat, @ViewBuilder placeholder: () -> Placeholder) {
        self.subject = subject
        self.size = size
        self.placeholder = placeholder()
    }

    public var body: some View {
        Group {
            if let artwork {
                ArtworkImage(artwork, width: size, height: size)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: subject) {
            artwork = nil
            guard let store else { return }
            artwork = await store.artwork(for: subject)
        }
    }
}
