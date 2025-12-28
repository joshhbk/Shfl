import Testing
import Foundation
@testable import Shfl

@Suite("LastFMQueue Tests")
struct LastFMQueueTests {

    @Test("Queue persists and loads events")
    func persistAndLoad() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await queue.enqueue(event)

        // Create new queue instance to test persistence
        let queue2 = LastFMQueue(storageURL: tempURL)
        let pending = await queue2.pending()

        #expect(pending.count == 1)
        #expect(pending.first?.track == "Test")
    }

    @Test("Dequeue removes event")
    func dequeueRemoves() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await queue.enqueue(event)
        let batch = await queue.dequeueBatch(limit: 10)
        await queue.confirmDequeued(batch)

        let pending = await queue.pending()
        #expect(pending.isEmpty)
    }

    @Test("Failed dequeue returns events to queue")
    func failedDequeueReturns() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        let event = ScrobbleEvent(
            track: "Test",
            artist: "Artist",
            album: "Album",
            timestamp: Date(),
            durationSeconds: 180
        )

        await queue.enqueue(event)
        let batch = await queue.dequeueBatch(limit: 10)
        await queue.returnToQueue(batch)  // Failed, return

        let pending = await queue.pending()
        #expect(pending.count == 1)
    }

    @Test("Batch respects limit")
    func batchLimit() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let queue = LastFMQueue(storageURL: tempURL)

        for i in 0..<10 {
            let event = ScrobbleEvent(
                track: "Track \(i)",
                artist: "Artist",
                album: "Album",
                timestamp: Date(),
                durationSeconds: 180
            )
            await queue.enqueue(event)
        }

        let batch = await queue.dequeueBatch(limit: 5)
        #expect(batch.count == 5)
    }
}
