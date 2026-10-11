import ShflCore

/// The tray's slots: picks oldest first, then the empty ones.
struct TraySlots: Equatable {
    enum Slot: Equatable {
        case picked(Song, joinsNextShuffle: Bool)
        /// `isMilestone`: filling this slot reaches a milestone.
        case empty(isMilestone: Bool)
    }

    let slots: [Slot]

    init(picks: [Song], capacity: Int, milestones: Set<Int>, joiningNextShuffle: Set<String>) {
        slots = (0..<capacity).map { index in
            guard index < picks.count else { return .empty(isMilestone: milestones.contains(index + 1)) }
            let song = picks[index]
            return .picked(song, joinsNextShuffle: joiningNextShuffle.contains(song.id))
        }
    }

    subscript(index: Int) -> Slot { slots[index] }
}
