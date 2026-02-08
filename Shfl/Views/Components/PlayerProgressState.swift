import Foundation

/// Timer-based progress tracking for playback position
@Observable @MainActor
final class PlayerProgressState {
    enum PollingMode: Equatable {
        case disabled
        case boosted
        case steady
    }

    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var pollingMode: PollingMode = .disabled

    private let musicService: MusicService
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var boostExpiryTask: Task<Void, Never>?
    private var isTrackingEnabled = false
    private var playbackState: PlaybackState = .empty
    private var boostUntil: Date?

    private let boostedUpdateInterval: TimeInterval
    private let steadyUpdateInterval: TimeInterval
    private let boostDuration: TimeInterval
    private let nowProvider: () -> Date
    private let timeUpdateThreshold: TimeInterval = 0.02
    private let durationUpdateThreshold: TimeInterval = 0.1

    var activeUpdateInterval: TimeInterval? {
        timerInterval
    }

    init(
        musicService: MusicService,
        boostedUpdateInterval: TimeInterval = 0.12,
        steadyUpdateInterval: TimeInterval = 0.45,
        boostDuration: TimeInterval = 2.5,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.musicService = musicService
        self.boostedUpdateInterval = boostedUpdateInterval
        self.steadyUpdateInterval = steadyUpdateInterval
        self.boostDuration = boostDuration
        self.nowProvider = nowProvider
    }

    func startUpdating(playbackState: PlaybackState = .empty) {
        stopUpdating()
        isTrackingEnabled = true
        self.playbackState = playbackState
        refreshNow()
        if playbackState.isPlaying {
            beginBoostWindow()
        }
        updatePollingSchedule()
    }

    func stopUpdating() {
        isTrackingEnabled = false
        clearBoostWindow()
        invalidateTimer()
    }

    func refreshDuration() {
        duration = musicService.currentSongDuration
    }

    func handlePlaybackStateChange(_ newState: PlaybackState) {
        playbackState = newState
        refreshNow()

        if newState.isPlaying {
            beginBoostWindow()
        } else {
            clearBoostWindow()
        }

        updatePollingSchedule()
    }

    /// Resets time to current playback position immediately (call on song change)
    func resetToCurrentPosition() {
        refreshNow()
    }

    /// Updates displayed time immediately after user-initiated seeks.
    func handleUserSeek(to time: TimeInterval) {
        setCurrentTime(time)
        beginBoostWindow()
        updatePollingSchedule()
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

    private func beginBoostWindow() {
        boostUntil = nowProvider().addingTimeInterval(boostDuration)
        boostExpiryTask?.cancel()
        boostExpiryTask = Task { [weak self] in
            guard let self else { return }

            let positiveDuration = max(0, self.boostDuration)
            guard positiveDuration > 0 else {
                self.handleBoostWindowExpired()
                return
            }

            let nanoseconds = UInt64((positiveDuration * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self.handleBoostWindowExpired()
        }
    }

    private func clearBoostWindow() {
        boostExpiryTask?.cancel()
        boostExpiryTask = nil
        boostUntil = nil
    }

    private func handleBoostWindowExpired() {
        if let boostUntil, boostUntil <= nowProvider() {
            self.boostUntil = nil
        }
        updatePollingSchedule()
    }

    private func updatePollingSchedule() {
        let newMode = Self.resolvePollingMode(
            isTrackingEnabled: isTrackingEnabled,
            playbackState: playbackState,
            now: nowProvider(),
            boostUntil: boostUntil
        )

        guard newMode != pollingMode else { return }
        pollingMode = newMode

        switch newMode {
        case .disabled:
            invalidateTimer()
        case .boosted:
            scheduleTimer(interval: boostedUpdateInterval)
        case .steady:
            scheduleTimer(interval: steadyUpdateInterval)
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        guard timerInterval != interval else { return }

        invalidateTimer()
        timerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNow()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
        timerInterval = nil
    }

    static func resolvePollingMode(
        isTrackingEnabled: Bool,
        playbackState: PlaybackState,
        now: Date,
        boostUntil: Date?
    ) -> PollingMode {
        guard isTrackingEnabled, playbackState.isPlaying else {
            return .disabled
        }

        if let boostUntil, boostUntil > now {
            return .boosted
        }

        return .steady
    }
}
