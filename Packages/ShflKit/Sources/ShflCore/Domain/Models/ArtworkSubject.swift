import Foundation

public nonisolated enum ArtworkSubject: Hashable, Sendable {
    case song(id: String)
    case artist(id: String)
    case playlist(id: String)
}
