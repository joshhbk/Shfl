import XCTest
@testable import ShflCore

final class SongCodingTests: XCTestCase {
    func testRoundTripKeepsDurationAndDateAdded() throws {
        let song = Song(
            id: "1",
            title: "Kyoto",
            artist: "Phoebe Bridgers",
            albumTitle: "Punisher",
            artworkURL: nil,
            playCount: 212,
            duration: 184,
            dateAdded: Date(timeIntervalSinceReferenceDate: 812_000_000)
        )

        let decoded = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))

        XCTAssertEqual(decoded, song)
    }

    func testSongsSavedBeforeDurationDecodeWithoutIt() throws {
        let json = Data(#"{"id":"1","title":"Kyoto","artist":"Phoebe Bridgers","albumTitle":"Punisher","playCount":3}"#.utf8)

        let decoded = try JSONDecoder().decode(Song.self, from: json)

        XCTAssertNil(decoded.duration)
        XCTAssertNil(decoded.dateAdded)
    }
}
