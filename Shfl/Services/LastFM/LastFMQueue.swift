import Foundation

actor LastFMQueue {
    private let storageURL: URL
    private var events: [ScrobbleEvent]
    private var inFlight: [ScrobbleEvent] = []

    init(storageURL: URL? = nil) {
        let url = storageURL ?? Self.defaultStorageURL()
        self.storageURL = url
        self.events = Self.loadEventsFromDisk(at: url)
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
        let batch = Array(events.prefix(limit))
        inFlight = batch
        events.removeFirst(min(limit, events.count))
        saveToDisk()
        return batch
    }

    func confirmDequeued(_ batch: [ScrobbleEvent]) {
        inFlight.removeAll { event in
            batch.contains { $0 == event }
        }
    }

    func returnToQueue(_ batch: [ScrobbleEvent]) {
        events.insert(contentsOf: batch, at: 0)
        inFlight.removeAll { event in
            batch.contains { $0 == event }
        }
        saveToDisk()
    }

    // MARK: - Persistence

    private static func loadEventsFromDisk(at url: URL) -> [ScrobbleEvent] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([ScrobbleEvent].self, from: data)
        } catch {
            // If we can't load, start fresh
            return []
        }
    }

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Log error in production
        }
    }
}
