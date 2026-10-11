import ShflCore

enum SidebarItem: Hashable, CaseIterable {
    case songs
    case artists
    case playlists

    var title: String {
        switch self {
        case .songs: "Songs"
        case .artists: "Artists"
        case .playlists: "Playlists"
        }
    }

    var searchPrompt: String { "Search \(title)" }

    var systemImage: String {
        switch self {
        case .songs: "music.note"
        case .artists: "music.mic"
        case .playlists: "music.note.list"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .songs: "mac.sidebar.songs"
        case .artists: "mac.sidebar.artists"
        case .playlists: "mac.sidebar.playlists"
        }
    }

    var libraryLane: LibraryLaneKind {
        switch self {
        case .songs: .songs
        case .artists: .artists
        case .playlists: .playlists
        }
    }
}
