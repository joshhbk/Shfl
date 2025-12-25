import Foundation

struct Song: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let albumTitle: String
    let artworkURL: URL?
}
