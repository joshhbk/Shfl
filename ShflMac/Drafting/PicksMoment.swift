/// Something the Picks column marks as it happens. `id` tells two of the same kind apart.
struct PicksMoment: Equatable {
    enum Kind: Equatable {
        case milestone(Int)
        /// A batch didn't fit, so nothing was added.
        case noRoom
    }

    let kind: Kind
    let id: Int
}
