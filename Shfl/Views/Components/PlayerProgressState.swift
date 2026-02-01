import Foundation

/// Timer-based progress tracking for playback position
@Observable @MainActor
final class PlayerProgressState {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private let musicService: MusicService
    private var timer: Timer?

    init(musicService: MusicService) {
        self.musicService = musicService
    }

    func startUpdating() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = self.musicService.currentPlaybackTime
                self.duration = self.musicService.currentSongDuration
            }
        }
    }

    func stopUpdating() {
        timer?.invalidate()
        timer = nil
    }

    func refreshDuration() {
        duration = musicService.currentSongDuration
    }

    /// Resets time to current playback position immediately (call on song change)
    func resetToCurrentPosition() {
        currentTime = musicService.currentPlaybackTime
        duration = musicService.currentSongDuration
    }
}
