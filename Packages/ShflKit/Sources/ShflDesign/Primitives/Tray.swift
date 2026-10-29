import SwiftUI

/// A grid of square tiles, with a ruler naming each row that ends on one of `marks`. Marks up to `filled`
/// step up in weight and colour.
public struct Tray<Tile: View>: View {
    private let capacity: Int
    private let filled: Int
    private let columns: Int
    private let marks: Set<Int>
    private let tile: (Int) -> Tile

    public init(
        capacity: Int,
        filled: Int,
        columns: Int = 10,
        marks: Set<Int>,
        @ViewBuilder tile: @escaping (Int) -> Tile
    ) {
        self.capacity = capacity
        self.filled = filled
        self.columns = columns
        self.marks = marks
        self.tile = tile
    }

    public var body: some View {
        let rows = (capacity + columns - 1) / columns
        Grid(horizontalSpacing: TrayMetrics.gap, verticalSpacing: TrayMetrics.gap) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < capacity {
                            tile(index)
                        } else {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                        }
                    }
                    let rowEnd = min((row + 1) * columns, capacity)
                    RulerMark(rowEnd: rowEnd, isMarked: marks.contains(rowEnd), isReached: rowEnd <= filled)
                }
            }
        }
    }
}

enum TrayMetrics {
    static let gap: CGFloat = 4
    static let rulerWidth: CGFloat = 26
}

private struct RulerMark: View {
    let rowEnd: Int
    let isMarked: Bool
    let isReached: Bool

    var body: some View {
        Group {
            if isMarked {
                Text(rowEnd, format: .number)
                    .font(isReached ? .rulerMarkReached.monospacedDigit() : .rulerMark.monospacedDigit())
                    .foregroundStyle(isReached ? AnyShapeStyle(.accentText) : AnyShapeStyle(.tertiary))
            } else {
                Color.clear.gridCellUnsizedAxes(.vertical)
            }
        }
        .frame(width: TrayMetrics.rulerWidth, alignment: .leading)
        .padding(.leading, TrayMetrics.gap)
        .accessibilityHidden(true)
    }
}

/// A tray tile for a picked song, in its artwork's colour, or neutral grey without one.
public struct PickedTile: View {
    private let tone: Color?

    public init(tone: Color?) {
        self.tone = tone
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.tile)
            .fill(tone.map(AnyShapeStyle.init) ?? AnyShapeStyle(.tileNeutral))
            .aspectRatio(1, contentMode: .fit)
    }
}

public struct EmptyTile: View {
    public init() {}

    public var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.tile)
            .fill(.traySlot)
            .aspectRatio(1, contentMode: .fit)
    }
}

extension View {
    /// Rings a tile picked since the shuffle that's playing.
    public func tileRing(_ isRinged: Bool) -> some View {
        overlay {
            if isRinged {
                RoundedRectangle(cornerRadius: CornerRadius.tile + 3)
                    .strokeBorder(.accentText, lineWidth: 1.5)
                    .padding(-3)
            }
        }
    }

    /// Outlines an empty slot that reaches a milestone when filled.
    public func milestoneOutline(_ isOutlined: Bool) -> some View {
        overlay {
            if isOutlined {
                RoundedRectangle(cornerRadius: CornerRadius.tile)
                    .strokeBorder(.tertiary, lineWidth: 1.5)
            }
        }
    }
}

extension View {
    /// The keyboard focus ring on a tile: 3pt in the theme colour, outside the tile.
    public func tileFocus(_ isFocused: Bool) -> some View {
        overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: CornerRadius.tile + 4)
                    .strokeBorder(.accentFill, lineWidth: 3)
                    .padding(-4)
            }
        }
        .zIndex(isFocused ? 1 : 0)
    }
}
