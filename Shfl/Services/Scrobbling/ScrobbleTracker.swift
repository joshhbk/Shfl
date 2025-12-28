import Foundation

@MainActor
final class ScrobbleTracker {
    private let scrobbleManager: ScrobbleManager
    private let musicService: MusicService

    init(scrobbleManager: ScrobbleManager, musicService: MusicService) {
        self.scrobbleManager = scrobbleManager
        self.musicService = musicService
    }

    // MARK: - Threshold Calculation (nonisolated static for testability)

    nonisolated static let minimumDurationForScrobble: Int = 30
    nonisolated static let maximumThresholdSeconds: Int = 240  // 4 minutes

    nonisolated static func shouldScrobble(durationSeconds: Int) -> Bool {
        durationSeconds >= minimumDurationForScrobble
    }

    nonisolated static func scrobbleThreshold(forDurationSeconds duration: Int) -> Int {
        min(duration / 2, maximumThresholdSeconds)
    }
}
