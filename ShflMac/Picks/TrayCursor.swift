/// Where the keyboard is in the tray: an index into the picks, moved a tile or a row at a time.
struct TrayCursor: Equatable {
    enum Step {
        case left, right, up, down
    }

    private(set) var index: Int

    /// Starts on the newest pick, or nil when there are none.
    init?(count: Int) {
        guard count > 0 else { return nil }
        index = count - 1
    }

    init(index: Int) {
        self.index = index
    }

    mutating func move(_ step: Step, count: Int, columns: Int) {
        let target = switch step {
        case .left: index - 1
        case .right: index + 1
        case .up: index - columns
        case .down: index + columns
        }
        if (0..<count).contains(target) { index = target }
    }

    /// Keeps the cursor on a pick after one is removed; nil once none are left.
    func clamped(to count: Int) -> TrayCursor? {
        guard count > 0 else { return nil }
        var cursor = self
        cursor.index = min(index, count - 1)
        return cursor
    }
}
