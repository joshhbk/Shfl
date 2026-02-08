import Foundation

/// Timer-based progress tracking for playback position
@Observable @MainActor
final class PlayerProgressState {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    private let musicService: MusicService
    private var timer: Timer?
    private let updateInterval: TimeInterval = 0.2
    private let timeUpdateThreshold: TimeInterval = 0.02
    private let durationUpdateThreshold: TimeInterval = 0.1

    init(musicService: MusicService) {
        self.musicService = musicService
    }

    func startUpdating() {
        stopUpdating()
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
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
        refreshNow()
    }

    /// Updates displayed time immediately after user-initiated seeks.
    func setCurrentTime(_ time: TimeInterval) {
        let upperBound = duration > 0 ? duration : time
        currentTime = min(max(0, time), upperBound)
    }

    private func refreshNow() {
        let newTime = musicService.currentPlaybackTime
        let newDuration = musicService.currentSongDuration
        if abs(newTime - currentTime) > timeUpdateThreshold {
            currentTime = newTime
        }
        if abs(newDuration - duration) > durationUpdateThreshold {
            duration = newDuration
        }
    }
}
