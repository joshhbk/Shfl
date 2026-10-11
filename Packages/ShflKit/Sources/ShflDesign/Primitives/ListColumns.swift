import SwiftUI

/// One column of a list: its width and which edge its content sits on. Rows and their header list the
/// same columns, in order.
public struct ListColumn: Hashable, Sendable {
    private let id: String
    let width: Width
    let isTrailing: Bool

    public static let artwork = ListColumn(id: "artwork", width: .fixed(ArtworkSize.songRow), isTrailing: false)
    public static let title = ListColumn(id: "title", width: .share(1.6), isTrailing: false)
    public static let detail = ListColumn(id: "detail", width: .share(1), isTrailing: false)
    public static let time = ListColumn(id: "time", width: .fixed(44), isTrailing: true)
    public static let accessory = ListColumn(id: "accessory", width: .fixed(26), isTrailing: false)

    /// A right-aligned number or date, as wide as its longest value or heading.
    public static func stat(_ id: String, width: CGFloat) -> ListColumn {
        ListColumn(id: id, width: .fixed(width), isTrailing: true)
    }

    enum Width: Hashable, Sendable {
        case fixed(CGFloat)
        case share(CGFloat)
    }
}

/// Lays out a header and its rows in the same columns. Give every child one of `columns` with `.listColumn(_:)`.
public struct ListColumns: Layout {
    private let columns: [ListColumn]

    public init(_ columns: [ListColumn]) {
        self.columns = columns
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
                assertionFailure("Every ListColumns child needs one of its columns: \(columns)")
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
