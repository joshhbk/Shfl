import ShflCore
import SwiftUI

/// A 44pt rounded artwork tile for list rows, with an icon for the kind of
/// item until its artwork loads.
struct EntityArtwork: View {
    let subject: ArtworkSubject

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.gray.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay {
                ArtworkView(subject: subject, size: 44) {
                    Image(systemName: iconName)
                        .foregroundStyle(.gray)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
    }

    private var iconName: String {
        switch subject {
        case .song: "music.note"
        case .artist: "person.fill"
        case .playlist: "music.note.list"
        }
    }
}
