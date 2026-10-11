import SwiftUI

/// A role in a list row. Each has its own width, and `stat` and `time` sit on the trailing edge.
public enum ListColumn: Int, CaseIterable, Comparable, Sendable {
    case artwork
    case title
    case detail
    case stat
    case time
    case accessory

    public static func < (lhs: ListColumn, rhs: ListColumn) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var width: Width {
        switch self {
        case .artwork: .fixed(ArtworkSize.songRow)
        case .title: .share(1.6)
        case .detail: .share(1)
        case .stat: .fixed(64)
        case .time: .fixed(44)
        case .accessory: .fixed(26)
        }
    }

    var isTrailing: Bool { self == .stat || self == .time }

    enum Width: Equatable {
        case fixed(CGFloat)
        case share(CGFloat)
    }
}

/// Lays out a header and its rows in the same columns. Give each child a role with `.listColumn(_:)`;
/// children whose role isn't in `columns` are hidden.
public struct ListColumns: Layout {
    private let columns: [ListColumn]

    public init(_ columns: Set<ListColumn>) {
        self.columns = columns.sorted()
    }

    static let gap: CGFloat = 12
    private static let idealWidth: CGFloat = 640

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? Self.idealWidth
        let frames = Self.columnFrames(columns, in: width)
        let height = subviews.reduce(CGFloat.zero) { tallest, subview in
            guard let frame = subview[ListColumnKey.self].flatMap({ frames[$0] }) else { return tallest }
            return max(tallest, subview.sizeThatFits(ProposedViewSize(width: frame.width, height: proposal.height)).height)
        }
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = Self.columnFrames(columns, in: bounds.width)
        for subview in subviews {
            guard let column = subview[ListColumnKey.self], let frame = frames[column] else {
                subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY), proposal: .zero)
                continue
            }
            let x = bounds.minX + (column.isTrailing ? frame.maxX : frame.minX)
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: column.isTrailing ? .trailing : .leading,
                proposal: ProposedViewSize(width: frame.width, height: bounds.height)
            )
        }
    }

    /// Each column's horizontal span, from zero.
    static func columnFrames(_ columns: [ListColumn], in width: CGFloat) -> [ListColumn: ClosedRange<CGFloat>] {
        let gaps = gap * CGFloat(max(columns.count - 1, 0))
        let fixed = columns.reduce(CGFloat.zero) { total, column in
            if case .fixed(let width) = column.width { total + width } else { total }
        }
        let shares = columns.reduce(CGFloat.zero) { total, column in
            if case .share(let share) = column.width { total + share } else { total }
        }
        let flexible = max(width - fixed - gaps, 0)

        var frames: [ListColumn: ClosedRange<CGFloat>] = [:]
        var x: CGFloat = 0
        for column in columns {
            let columnWidth = switch column.width {
            case .fixed(let width): width
            case .share(let share): shares > 0 ? flexible * share / shares : 0
            }
            frames[column] = x...(x + columnWidth)
            x += columnWidth + gap
        }
        return frames
    }

}

private struct ListColumnKey: LayoutValueKey {
    static let defaultValue: ListColumn? = nil
}

extension View {
    public func listColumn(_ column: ListColumn) -> some View {
        layoutValue(key: ListColumnKey.self, value: column)
    }
}

private extension ClosedRange where Bound == CGFloat {
    var width: CGFloat { upperBound - lowerBound }
    var minX: CGFloat { lowerBound }
    var maxX: CGFloat { upperBound }
}
