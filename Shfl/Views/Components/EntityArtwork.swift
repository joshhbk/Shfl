import Combine
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
            .onAppear {
                artwork = ArtworkCache.shared.artwork(for: entityId)
                if artwork == nil {
                    ArtworkCache.shared.requestArtwork(for: entityId, type: type)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: ArtworkCache.artworkDidLoad)
                    .filter { ($0.userInfo?["songId"] as? String) == entityId }
            ) { _ in
                artwork = ArtworkCache.shared.artwork(for: entityId)
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
