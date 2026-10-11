import SwiftUI

/// A grid of square tiles, with a ruler naming each row that ends on one of `marks`.
public struct Tray<Tile: View>: View {
    private let capacity: Int
    private let columns: Int
    private let marks: Set<Int>
    private let tile: (Int) -> Tile

    public init(capacity: Int, columns: Int = 10, marks: Set<Int>, @ViewBuilder tile: @escaping (Int) -> Tile) {
        self.capacity = capacity
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
                    RulerMark(rowEnd: min((row + 1) * columns, capacity), marks: marks)
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
    let marks: Set<Int>

    var body: some View {
        Group {
            if marks.contains(rowEnd) {
                Text(rowEnd, format: .number)
                    .font(.rulerMark.monospacedDigit())
                    .foregroundStyle(.tertiary)
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
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.tile)
                    .strokeBorder(.gray.opacity(0.3), lineWidth: 1)
            }
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
