import XCTest
@testable import ShflCore
@testable import ShflDeterministic

@MainActor
final class CollectionLoadingTests: XCTestCase {
    func test_loadingAllSongsFetchesEveryPage() async {
        let songs = (1...130).map { index in
            Song(id: "\(index)", title: "Song \(index)", artist: "Beach House", albumTitle: "Bloom", artworkURL: nil)
        }
        let other = Song(id: "x", title: "Kyoto", artist: "Phoebe Bridgers", albumTitle: "Punisher", artworkURL: nil)
        let catalog = DeterministicMusicService(library: DeterministicLibrary(songs: songs + [other]))
        let artist = ArtistDetailViewModel(artist: Artist(id: "a", name: "Beach House"), libraryCatalog: catalog)

        XCTAssertFalse(artist.hasLoadedAllSongs)
        await artist.loadAllSongs()

        XCTAssertEqual(artist.songs.count, 130)
        XCTAssertTrue(artist.hasLoadedAllSongs)
    }

    func test_loadingAllOfAPlaylistFetchesEveryPage() async {
        let songs = (1...75).map { Song(id: "\($0)", title: "Song \($0)", artist: "Lorde", albumTitle: "Melodrama", artworkURL: nil) }
        let mix = Playlist(id: "p", name: "Kitchen Dancing")
        let catalog = DeterministicMusicService(library: DeterministicLibrary(songs: songs, playlists: [mix], playlistSongs: ["p": songs]))
        let playlist = PlaylistDetailViewModel(playlist: mix, libraryCatalog: catalog)

        await playlist.loadAllSongs()

        XCTAssertEqual(playlist.songs.count, 75)
        XCTAssertTrue(playlist.hasLoadedAllSongs)
    }

    func test_songsMatchOnTitleArtistOrAlbum() {
        let song = Song(id: "1", title: "Space Song", artist: "Beach House", albumTitle: "Depression Cherry", artworkURL: nil)
        XCTAssertTrue(song.matches(""))
        XCTAssertTrue(song.matches("space"))
        XCTAssertTrue(song.matches("beach"))
        XCTAssertTrue(song.matches("cherry"))
        XCTAssertFalse(song.matches("kyoto"))
    }
}
