/// Which tiles react to each moment, and the triggers that start them. Triggers only count up, so a tile
/// that sat one beat out doesn't replay when the next one starts.
struct TrayMotion: Equatable {
    static let rippleStep = 0.024

    private(set) var milestoneBeats = 0
    private(set) var milestone: Int?
    private(set) var noRoomFlashes = 0

    mutating func play(_ kind: PicksMoment.Kind) {
        switch kind {
        case .milestone(let reached):
            milestone = reached
            milestoneBeats += 1
        case .noRoom:
            noRoomFlashes += 1
        }
    }

    /// When tile `index` pops in the current milestone beat, or nil if it sits it out.
    func pulseDelay(for index: Int, capacity: Int, columns: Int) -> Double? {
        guard let milestone, index < milestone else { return nil }
        if milestone == 1 || milestone == capacity { return 0 }
        guard index / columns == (milestone - 1) / columns else { return nil }
        return Double(index % columns) * Self.rippleStep
    }
}
