import Foundation
import Testing
@testable import Shfl

@Suite("LastFMTransport Tests")
struct LastFMTransportTests {

    @Test("decodeRecentTracks maps now-playing, timestamp, and artwork")
    func decodeRecentTracksMapsFields() throws {
        let json = """
        {
          "recenttracks": {
            "track": [
              {
                "name": "Tokyo Summer",
                "artist": { "#text": "Mounties" },
                "image": [
                  { "#text": "https://img.test/small.jpg", "size": "small" },
                  { "#text": "https://img.test/large.jpg", "size": "large" }
                ],
                "date": { "uts": "1700000000" }
              },
              {
                "name": "No Days Off",
                "artist": { "#text": "Kamakaze" },
                "image": [
                  { "#text": "", "size": "medium" }
                ],
                "@attr": { "nowplaying": "true" }
              }
            ]
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let tracks = try LastFMTransport.decodeRecentTracks(from: data, limit: 20)

        #expect(tracks.count == 2)

        let first = try #require(tracks.first)
        #expect(first.title == "Tokyo Summer")
        #expect(first.artist == "Mounties")
        #expect(first.isNowPlaying == false)
        #expect(first.playedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(first.artworkURL?.absoluteString == "https://img.test/large.jpg")

        let second = try #require(tracks.last)
        #expect(second.title == "No Days Off")
        #expect(second.artist == "Kamakaze")
        #expect(second.isNowPlaying == true)
        #expect(second.playedAt == nil)
        #expect(second.artworkURL == nil)
    }

    @Test("decodeRecentTracks respects requested limit")
    func decodeRecentTracksRespectsLimit() throws {
        let json = """
        {
          "recenttracks": {
            "track": [
              { "name": "One", "artist": { "#text": "A" }, "image": [] },
              { "name": "Two", "artist": { "#text": "B" }, "image": [] },
              { "name": "Three", "artist": { "#text": "C" }, "image": [] }
            ]
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let tracks = try LastFMTransport.decodeRecentTracks(from: data, limit: 1)

        #expect(tracks.count == 1)
        #expect(tracks.first?.title == "One")
    }

    @Test("decodeRecentTracks accepts string-valued artist payload")
    func decodeRecentTracksAcceptsStringArtist() throws {
        let json = """
        {
          "recenttracks": {
            "track": [
              {
                "name": "Track",
                "artist": "String Artist",
                "image": []
              }
            ]
          }
        }
        """

        let data = try #require(json.data(using: .utf8))
        let tracks = try LastFMTransport.decodeRecentTracks(from: data, limit: 10)

        #expect(tracks.count == 1)
        #expect(tracks.first?.artist == "String Artist")
    }
}
