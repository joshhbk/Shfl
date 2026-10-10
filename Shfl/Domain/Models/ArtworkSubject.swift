import Foundation

/// The library item whose artwork a view wants drawn. Shells hand this to the
/// platform's artwork store; the core never sees the artwork itself.
nonisolated enum ArtworkSubject: Hashable, Sendable {
    case song(id: String)
    case artist(id: String)
    case playlist(id: String)
}
