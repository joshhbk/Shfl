import Testing
import Foundation
@testable import Shfl

@Suite("LastFMQueue Tests")
struct LastFMQueueTests {
    private func makeTempQueueURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private func makeEvent(track: String) -> ScrobbleEvent {
        ScrobbleEvent(
            track: track,
            artist: "Artist",
            album: "Album",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 180
        )
    }

    @Test("Queue persists and loads events")
    func persistAndLoad() async throws {
        let tempURL = makeTempQueueURL()

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)
        let event = makeEvent(track: "Test")

        await queue.enqueue(event)

        // Create new queue instance to test persistence
        let queue2 = LastFMQueue(storageURL: tempURL)
        let pending = await queue2.pending()

        #expect(pending.count == 1)
        #expect(pending.first?.track == "Test")
    }

    @Test("Dequeue removes event")
    func dequeueRemoves() async throws {
        let tempURL = makeTempQueueURL()

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)
        let event = makeEvent(track: "Test")

        await queue.enqueue(event)
        let batch = await queue.dequeueBatch(limit: 10)
        await queue.confirmDequeued(batch)

        let pending = await queue.pending()
        #expect(pending.isEmpty)
    }

    @Test("Failed dequeue returns events to queue")
    func failedDequeueReturns() async throws {
        let tempURL = makeTempQueueURL()

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)
        let event = makeEvent(track: "Test")

        await queue.enqueue(event)
        let batch = await queue.dequeueBatch(limit: 10)
        await queue.returnToQueue(batch)  // Failed, return

        let pending = await queue.pending()
        #expect(pending.count == 1)
    }

    @Test("Batch respects limit")
    func batchLimit() async throws {
        let tempURL = makeTempQueueURL()

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        for i in 0..<10 {
            await queue.enqueue(makeEvent(track: "Track \(i)"))
        }

        let batch = await queue.dequeueBatch(limit: 5)
        #expect(batch.count == 5)
    }

    @Test("In-flight events are recovered on restart")
    func recoverInFlightOnRestart() async throws {
        let tempURL = makeTempQueueURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)
        await queue.enqueue(makeEvent(track: "First"))
        await queue.enqueue(makeEvent(track: "Second"))

        let batch = await queue.dequeueBatch(limit: 1)
        #expect(batch.count == 1)

        // Simulate app restart before confirm/return.
        let restartedQueue = LastFMQueue(storageURL: tempURL)
        let pending = await restartedQueue.pending()

        #expect(pending.count == 2)
        #expect(pending.map(\.track) == ["First", "Second"])
    }

    @Test("Confirmed dequeued events are not replayed after restart")
    func confirmedEventsNotReplayed() async throws {
        let tempURL = makeTempQueueURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)
        await queue.enqueue(makeEvent(track: "First"))
        await queue.enqueue(makeEvent(track: "Second"))

        let batch = await queue.dequeueBatch(limit: 1)
        await queue.confirmDequeued(batch)

        let restartedQueue = LastFMQueue(storageURL: tempURL)
        let pending = await restartedQueue.pending()

        #expect(pending.count == 1)
        #expect(pending.first?.track == "Second")
    }

    @Test("Legacy queue file with pending-only array still loads")
    func loadLegacyPendingOnlyFormat() async throws {
        let tempURL = makeTempQueueURL()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let legacyEvents = [makeEvent(track: "Legacy")]
        let legacyData = try JSONEncoder().encode(legacyEvents)
        try legacyData.write(to: tempURL, options: .atomic)

        let queue = LastFMQueue(storageURL: tempURL)
        let pending = await queue.pending()

        #expect(pending.count == 1)
        #expect(pending.first?.track == "Legacy")
    }
}
