import Foundation

/// Best-effort persistent queue for Last.fm scrobbles.
/// If the app terminates during flush, in-flight events are replayed on next launch.
/// This may cause duplicate sends, which is an accepted tradeoff to avoid silent drops.
actor LastFMQueue {
    private let storageURL: URL
    private var events: [ScrobbleEvent]
    private var inFlight: [ScrobbleEvent] = []

    init(storageURL: URL? = nil) {
        let url = storageURL ?? Self.defaultStorageURL()
        self.storageURL = url
        let restoredState = Self.loadQueueStateFromDisk(at: url)
        let recoveredInFlight = restoredState.inFlight

        // Best-effort crash recovery: replay unfinished in-flight events first.
        self.events = recoveredInFlight + restoredState.pending
        self.inFlight = []

        if !recoveredInFlight.isEmpty {
            Self.saveQueueState(
                LastFMQueueSnapshot(pending: self.events, inFlight: []),
                to: url
            )
        }
    }

    private static func defaultStorageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let shflDir = appSupport.appendingPathComponent("Shfl", isDirectory: true)
        try? FileManager.default.createDirectory(at: shflDir, withIntermediateDirectories: true)
        return shflDir.appendingPathComponent("lastfm_queue.json")
    }

    func enqueue(_ event: ScrobbleEvent) {
        events.append(event)
        saveToDisk()
    }

    func pending() -> [ScrobbleEvent] {
        events
    }

    func dequeueBatch(limit: Int) -> [ScrobbleEvent] {
        guard limit > 0 else { return [] }
        let batch = Array(events.prefix(limit))
        inFlight.append(contentsOf: batch)
        events.removeFirst(min(limit, events.count))
        saveToDisk()
        return batch
    }

    func confirmDequeued(_ batch: [ScrobbleEvent]) {
        inFlight.removeAll { event in
            batch.contains { $0 == event }
        }
        saveToDisk()
    }

    func returnToQueue(_ batch: [ScrobbleEvent]) {
        events.insert(contentsOf: batch, at: 0)
        inFlight.removeAll { event in
            batch.contains { $0 == event }
        }
        saveToDisk()
    }

    // MARK: - Persistence

    private static func loadQueueStateFromDisk(at url: URL) -> LastFMQueueSnapshot {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return LastFMQueueSnapshot(pending: [], inFlight: [])
        }
        do {
            let data = try Data(contentsOf: url)

            // New format with pending + inFlight persistence.
            if let snapshot = try? JSONDecoder().decode(LastFMQueueSnapshot.self, from: data) {
                return snapshot
            }

            // Legacy format (pending array only).
            let pending = try JSONDecoder().decode([ScrobbleEvent].self, from: data)
            return LastFMQueueSnapshot(pending: pending, inFlight: [])
        } catch {
            // If we can't load, start fresh
            return LastFMQueueSnapshot(pending: [], inFlight: [])
        }
    }

    private func saveToDisk() {
        let snapshot = LastFMQueueSnapshot(pending: events, inFlight: inFlight)
        Self.saveQueueState(snapshot, to: storageURL)
    }

    private static func saveQueueState(_ snapshot: LastFMQueueSnapshot, to url: URL) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            // Log error in production
        }
    }
}

nonisolated private struct LastFMQueueSnapshot: Codable, Sendable {
    var pending: [ScrobbleEvent]
    var inFlight: [ScrobbleEvent]
}
