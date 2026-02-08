import MusicKit
import SwiftUI

struct EntityArtwork: View {
    let entityId: String
    let type: ArtworkCache.ArtworkType

    @State private var artwork: Artwork?

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                if let artwork {
                    ArtworkImage(artwork, width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: iconName)
                        .foregroundStyle(.gray)
                }
            }
            .task(id: entityId) {
                artwork = ArtworkCache.shared.artwork(for: entityId)
                guard artwork == nil else { return }

                ArtworkCache.shared.requestArtwork(for: entityId, type: type)

                for await loadedArtwork in ArtworkCache.shared.artworkUpdates(for: entityId) {
                    artwork = loadedArtwork
                    break
                }
            }
    }

    private var iconName: String {
        switch type {
        case .song: "music.note"
        case .artist: "person.fill"
        case .playlist: "music.note.list"
        }
    }
}
