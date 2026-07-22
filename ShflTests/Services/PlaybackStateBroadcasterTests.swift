import XCTest
@testable import Shfl

@MainActor
final class PlaybackEventBroadcasterTests: XCTestCase {
    func testMultipleSubscribersReceiveStateAndSessionEndEvents() async {
        let broadcaster = PlaybackEventBroadcaster()
        let song = makeSong()
        let streamA = broadcaster.stream(replaying: .stateChanged(.empty))
        let streamB = broadcaster.stream(replaying: .stateChanged(.empty))

        broadcaster.publish(.stateChanged(.playing(song)))
        broadcaster.publish(.sessionEnded)

        let expected: [PlaybackEvent] = [
            .stateChanged(.empty),
            .stateChanged(.playing(song)),
            .sessionEnded
        ]
        let eventsA = await collect(from: streamA, count: 3)
        let eventsB = await collect(from: streamB, count: 3)
        XCTAssertEqual(eventsA, expected)
        XCTAssertEqual(eventsB, expected)
    }

    func testDuplicateEventsAreNotRepublished() async {
        let broadcaster = PlaybackEventBroadcaster()
        let song = makeSong()
        let stream = broadcaster.stream(replaying: .stateChanged(.empty))

        broadcaster.publish(.stateChanged(.empty))
        broadcaster.publish(.stateChanged(.playing(song)))
        broadcaster.publish(.stateChanged(.playing(song)))

        let events = await collect(from: stream, count: 2)
        XCTAssertEqual(events, [.stateChanged(.empty), .stateChanged(.playing(song))])
    }

    private func makeSong() -> Song {
        Song(
            id: "song-1",
            title: "Song",
            artist: "Artist",
            albumTitle: "Album",
            artworkURL: nil
        )
    }

    private func collect(
        from stream: AsyncStream<PlaybackEvent>,
        count: Int
    ) async -> [PlaybackEvent] {
        var result: [PlaybackEvent] = []
        var iterator = stream.makeAsyncIterator()
        for _ in 0..<count {
            guard let event = await iterator.next() else { break }
            result.append(event)
        }
        return result
    }
}
