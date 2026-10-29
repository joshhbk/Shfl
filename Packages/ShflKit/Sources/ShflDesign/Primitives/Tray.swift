import SwiftUI

/// A grid of square tiles.
public struct Tray<Tile: View>: View {
    private let capacity: Int
    private let columns: Int
    private let tile: (Int) -> Tile

    public init(capacity: Int, columns: Int = 10, @ViewBuilder tile: @escaping (Int) -> Tile) {
        self.capacity = capacity
        self.columns = columns
        self.tile = tile
    }

    public var body: some View {
        let rows = (capacity + columns - 1) / columns
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
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
                }
            }
        }
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
