import Foundation
import MusicKit
import ShflCore

/// MusicKit authorization and library catalog. Playback lives in
/// `MusicKitTransport`.
///
/// Nonisolated: it holds no state, and MusicKit's library requests don't need
/// the main actor.
nonisolated final class AppleMusicService: MusicAuthorizing, LibraryCatalog {
    var isAuthorized: Bool {
        get async {
            MusicAuthorization.currentStatus == .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    func fetchLibrarySongs(
        sortedBy: SortOption,
        limit: Int,
        offset: Int
    ) async throws -> LibraryPage {
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.limit = limit
        request.offset = offset

        switch sortedBy {
        case .mostPlayed:
            request.sort(by: \.playCount, ascending: false)
        case .recentlyPlayed:
            request.sort(by: \.lastPlayedDate, ascending: false)
        case .recentlyAdded:
            request.sort(by: \.libraryAddedDate, ascending: false)
        case .alphabetical:
            request.sort(by: \.title, ascending: true)
        }

        let response = try await request.response()

        let songs = response.items.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        // hasMore is true if we got a full page (might be more)
        let hasMore = response.items.count == limit

        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func fetchLibraryArtists(limit: Int, offset: Int) async throws -> ArtistPage {
        var request = MusicLibraryRequest<MusicKit.Artist>()
        request.limit = limit
        request.offset = offset
        request.sort(by: \.name, ascending: true)

        let response = try await request.response()

        let artists = response.items.map { musicKitArtist in
            Artist(
                id: musicKitArtist.id.rawValue,
                name: musicKitArtist.name
            )
        }

        let hasMore = response.items.count == limit
        return ArtistPage(artists: artists, hasMore: hasMore)
    }

    func fetchLibraryPlaylists(limit: Int, offset: Int) async throws -> PlaylistPage {
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.limit = limit
        request.offset = offset
        request.sort(by: \.name, ascending: true)

        let response = try await request.response()

        let playlists = response.items.map { musicKitPlaylist in
            Playlist(
                id: musicKitPlaylist.id.rawValue,
                name: musicKitPlaylist.name
            )
        }

        let hasMore = response.items.count == limit
        return PlaylistPage(playlists: playlists, hasMore: hasMore)
    }

    func fetchSongs(byArtist artistName: String, limit: Int, offset: Int) async throws -> LibraryPage {
        var request = MusicLibraryRequest<MusicKit.Song>()
        request.limit = limit
        request.offset = offset
        request.filter(matching: \.artistName, equalTo: artistName)
        request.sort(by: \.title, ascending: true)

        let response = try await request.response()

        let songs = response.items.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        let hasMore = response.items.count == limit
        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func fetchSongs(byPlaylistId playlistId: String, limit: Int, offset: Int) async throws -> LibraryPage {
        // Fetch the playlist by ID, then get its tracks
        var request = MusicLibraryRequest<MusicKit.Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(playlistId))

        let response = try await request.response()

        guard let playlist = response.items.first else {
            return LibraryPage(songs: [], hasMore: false)
        }

        // Load the playlist's tracks
        let detailedPlaylist = try await playlist.with([.tracks])

        guard let tracks = detailedPlaylist.tracks else {
            return LibraryPage(songs: [], hasMore: false)
        }

        let allSongs = tracks.compactMap { track -> ShflCore.Song? in
            guard case .song(let musicKitSong) = track else { return nil }
            return Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        // Manual pagination over the track list
        let startIndex = min(offset, allSongs.count)
        let endIndex = min(offset + limit, allSongs.count)
        let songs = Array(allSongs[startIndex..<endIndex])
        let hasMore = endIndex < allSongs.count

        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func searchLibrarySongs(query: String, limit: Int, offset: Int) async throws -> LibraryPage {
        // Note: MusicLibrarySearchRequest doesn't support offset-based pagination.
        // We fetch with a higher limit and slice the results to simulate offset.
        // This is a workaround since MusicKit's nextBatch() requires storing the collection.
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Song.self])
        request.limit = offset + limit

        let response = try await request.response()

        let allSongs = response.songs.map { musicKitSong in
            Song(
                id: musicKitSong.id.rawValue,
                title: musicKitSong.title,
                artist: musicKitSong.artistName,
                albumTitle: musicKitSong.albumTitle ?? "",
                artworkURL: nil,
                playCount: musicKitSong.playCount ?? 0,
                lastPlayedDate: musicKitSong.lastPlayedDate
            )
        }

        // Slice to get only the requested page
        let startIndex = min(offset, allSongs.count)
        let endIndex = min(offset + limit, allSongs.count)
        let songs = Array(allSongs[startIndex..<endIndex])

        // hasMore if we got a full page (same logic as browse pagination)
        let hasMore = songs.count == limit

        return LibraryPage(songs: songs, hasMore: hasMore)
    }

    func searchLibraryArtists(query: String, limit: Int, offset: Int) async throws -> ArtistPage {
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Artist.self])
        request.limit = offset + limit

        let response = try await request.response()

        let allArtists = response.artists.map { musicKitArtist in
            Artist(
                id: musicKitArtist.id.rawValue,
                name: musicKitArtist.name
            )
        }

        let startIndex = min(offset, allArtists.count)
        let endIndex = min(offset + limit, allArtists.count)
        let artists = Array(allArtists[startIndex..<endIndex])
        let hasMore = artists.count == limit

        return ArtistPage(artists: artists, hasMore: hasMore)
    }

    func searchLibraryPlaylists(query: String, limit: Int, offset: Int) async throws -> PlaylistPage {
        var request = MusicLibrarySearchRequest(term: query, types: [MusicKit.Playlist.self])
        request.limit = offset + limit

        let response = try await request.response()

        let allPlaylists = response.playlists.map { musicKitPlaylist in
            Playlist(
                id: musicKitPlaylist.id.rawValue,
                name: musicKitPlaylist.name
            )
        }

        let startIndex = min(offset, allPlaylists.count)
        let endIndex = min(offset + limit, allPlaylists.count)
        let playlists = Array(allPlaylists[startIndex..<endIndex])
        let hasMore = playlists.count == limit

        return PlaylistPage(playlists: playlists, hasMore: hasMore)
    }
}
