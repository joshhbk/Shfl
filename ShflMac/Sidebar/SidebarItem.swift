import ShflCore

enum SidebarItem: Hashable, CaseIterable {
    case songs
    case artists
    case playlists
    case selected
    case upNext

    static let library: [SidebarItem] = [.songs, .artists, .playlists]

    var title: String {
        switch self {
        case .songs: "Songs"
        case .artists: "Artists"
        case .playlists: "Playlists"
        case .selected: "Selected"
        case .upNext: "Up Next"
        }
    }

    var systemImage: String {
        switch self {
        case .songs: "music.note"
        case .artists: "music.mic"
        case .playlists: "music.note.list"
        case .selected: "checkmark.circle"
        case .upNext: "list.number"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .songs: "mac.sidebar.songs"
        case .artists: "mac.sidebar.artists"
        case .playlists: "mac.sidebar.playlists"
        case .selected: "mac.sidebar.selected"
        case .upNext: "mac.sidebar.upNext"
        }
    }

    var libraryLane: LibraryLaneKind? {
        switch self {
        case .songs: .songs
        case .artists: .artists
        case .playlists: .playlists
        case .selected, .upNext: nil
        }
    }
}
