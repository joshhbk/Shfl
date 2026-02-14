import Foundation

enum PlaybackState: Equatable, Sendable {
    case empty
    case stopped
    case loading(Song)
    case playing(Song)
    case paused(Song)
    case error(Error)

    var currentSong: Song? {
        switch self {
        case .loading(let song), .playing(let song), .paused(let song):
            return song
        case .empty, .stopped, .error:
            return nil
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.empty, .empty), (.stopped, .stopped):
            return true
        case (.loading(let l), .loading(let r)),
             (.playing(let l), .playing(let r)),
             (.paused(let l), .paused(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l.localizedDescription == r.localizedDescription
        default:
            return false
        }
    }
}

extension PlaybackState {
    var isActive: Bool {
        switch self {
        case .playing, .paused, .loading:
            return true
        case .empty, .stopped, .error:
            return false
        }
    }

    var currentSongId: String? {
        currentSong?.id
    }
}
