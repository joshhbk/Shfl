import Foundation

@MainActor
final class ScrobbleTracker {
    private let scrobbleManager: ScrobbleManager
    private let musicService: any MusicService

    private var currentSong: Song?
    private var playStartTime: Date?
    private var accumulatedPlayTime: TimeInterval = 0
    private var hasScrobbledCurrentSong = false
    private var isPlaying = false

    init(scrobbleManager: ScrobbleManager, musicService: any MusicService) {
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

    // MARK: - Playback Tracking

    func onPlaybackStateChanged(_ state: PlaybackState) {
        switch state {
        case .playing(let song):
            if song.id != currentSong?.id {
                // New song
                resetTracking()
                currentSong = song
                sendNowPlaying(song)
            }
            startTracking()

        case .paused:
            pauseTracking()

        case .stopped, .empty, .error:
            resetTracking()

        case .loading:
            // Do nothing while loading
            break
        }
    }

    private func startTracking() {
        guard !isPlaying else { return }
        isPlaying = true
        playStartTime = Date()
    }

    private func pauseTracking() {
        guard isPlaying, let startTime = playStartTime else { return }
        isPlaying = false
        accumulatedPlayTime += Date().timeIntervalSince(startTime)
        playStartTime = nil
    }

    private func resetTracking() {
        currentSong = nil
        playStartTime = nil
        accumulatedPlayTime = 0
        hasScrobbledCurrentSong = false
        isPlaying = false
    }

    private func sendNowPlaying(_ song: Song) {
        let durationSeconds = Int(musicService.currentSongDuration)
        let event = ScrobbleEvent(
            track: song.title,
            artist: song.artist,
            album: song.albumTitle,
            timestamp: Date(),
            durationSeconds: durationSeconds
        )
        Task {
            await scrobbleManager.sendNowPlaying(event)
        }
    }

    private func checkAndScrobble() {
        guard !hasScrobbledCurrentSong,
              let song = currentSong else { return }

        let durationSeconds = Int(musicService.currentSongDuration)
        guard Self.shouldScrobble(durationSeconds: durationSeconds) else { return }

        let threshold = Self.scrobbleThreshold(forDurationSeconds: durationSeconds)
        let totalPlayTime = totalElapsedPlayTime()

        if Int(totalPlayTime) >= threshold {
            hasScrobbledCurrentSong = true
            scrobble(song, durationSeconds: durationSeconds)
        }
    }

    private func totalElapsedPlayTime() -> TimeInterval {
        var total = accumulatedPlayTime
        if isPlaying, let startTime = playStartTime {
            total += Date().timeIntervalSince(startTime)
        }
        return total
    }

    private func scrobble(_ song: Song, durationSeconds: Int) {
        let event = ScrobbleEvent(
            track: song.title,
            artist: song.artist,
            album: song.albumTitle,
            timestamp: Date(),
            durationSeconds: durationSeconds
        )
        Task {
            await scrobbleManager.scrobble(event)
        }
    }

    // MARK: - Testing Support

    func simulateTimeElapsed(seconds: TimeInterval) {
        // Only accumulate time if playing
        guard isPlaying else { return }
        accumulatedPlayTime += seconds
        checkAndScrobble()
    }
}
