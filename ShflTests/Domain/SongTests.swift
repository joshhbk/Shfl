import Foundation
import Testing
@testable import Shfl

@Suite("Song Model Tests")
struct SongTests {
    @Test("Song initialization sets all properties")
    func songInitialization() {
        let song = Song(
            id: "12345",
            title: "Test Song",
            artist: "Test Artist",
            albumTitle: "Test Album",
            artworkURL: nil
        )

        #expect(song.id == "12345")
        #expect(song.title == "Test Song")
        #expect(song.artist == "Test Artist")
        #expect(song.albumTitle == "Test Album")
        #expect(song.artworkURL == nil)
    }

    @Test("Songs with same ID are equal")
    func songEquatable() {
        let song1 = Song(id: "123", title: "A", artist: "B", albumTitle: "C", artworkURL: nil)
        let song2 = Song(id: "123", title: "A", artist: "B", albumTitle: "C", artworkURL: nil)
        let song3 = Song(id: "456", title: "A", artist: "B", albumTitle: "C", artworkURL: nil)

        #expect(song1 == song2)
        #expect(song1 != song3)
    }

    @Test("Song with artwork URL")
    func songWithArtwork() {
        let url = URL(string: "https://example.com/art.jpg")!
        let song = Song(id: "1", title: "T", artist: "A", albumTitle: "B", artworkURL: url)

        #expect(song.artworkURL == url)
    }
}
