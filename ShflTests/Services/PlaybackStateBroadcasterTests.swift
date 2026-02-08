import XCTest
@testable import Shfl

@MainActor
final class PlaybackStateBroadcasterTests: XCTestCase {
    func testMultipleSubscribersReceiveSamePublishedEvents() async {
        let broadcaster = PlaybackStateBroadcaster()
        let song = Song(
            id: "song-1",
            title: "Song 1",
            artist: "Artist",
            albumTitle: "Album",
            artworkURL: nil
        )

        let streamA = broadcaster.stream(replaying: .empty)
        let streamB = broadcaster.stream(replaying: .empty)

        broadcaster.publish(.playing(song))
        broadcaster.publish(.paused(song))

        let statesA = await collectStates(from: streamA, count: 3)
        let statesB = await collectStates(from: streamB, count: 3)

        XCTAssertEqual(statesA, [.empty, .playing(song), .paused(song)])
        XCTAssertEqual(statesB, [.empty, .playing(song), .paused(song)])
    }

    func testLateSubscriberReceivesLatestStateImmediately() async {
        let broadcaster = PlaybackStateBroadcaster()
        let song = Song(
            id: "song-2",
            title: "Song 2",
            artist: "Artist",
            albumTitle: "Album",
            artworkURL: nil
        )
        broadcaster.publish(.playing(song))

        let stream = broadcaster.stream(replaying: .playing(song))
        let first = await firstState(from: stream)

        XCTAssertEqual(first, .playing(song))
    }

    func testSubscriberCountTracksStreamLifecycle() async {
        let broadcaster = PlaybackStateBroadcaster()
        XCTAssertEqual(broadcaster.subscriberCount, 0)

        var stream: AsyncStream<PlaybackState>? = broadcaster.stream(replaying: .empty)
        XCTAssertEqual(broadcaster.subscriberCount, 1)

        stream = nil
        // Give AsyncStream a moment to run termination handler after stream deallocation.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(stream)
        XCTAssertEqual(broadcaster.subscriberCount, 0)
    }

    private func firstState(
        from stream: AsyncStream<PlaybackState>,
        timeoutNanoseconds: UInt64 = 200_000_000
    ) async -> PlaybackState? {
        await withTaskGroup(of: PlaybackState?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let value = await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    private func collectStates(
        from stream: AsyncStream<PlaybackState>,
        count: Int,
        timeoutNanoseconds: UInt64 = 200_000_000
    ) async -> [PlaybackState] {
        guard count > 0 else { return [] }

        var collected: [PlaybackState] = []
        var iterator = stream.makeAsyncIterator()

        for _ in 0..<count {
            let next = await withTaskGroup(of: PlaybackState?.self) { group in
                group.addTask {
                    await iterator.next()
                }

                group.addTask {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return nil
                }

                let value = await group.next() ?? nil
                group.cancelAll()
                return value
            }

            guard let next else { break }
            collected.append(next)
        }

        return collected
    }
}
