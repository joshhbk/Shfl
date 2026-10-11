import SwiftUI

/// Marks a song that was unpicked after the shuffle but still plays this session.
public struct OutlinedTag: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        TagText(text)
            .foregroundStyle(.primary)
            .overlay {
                RoundedRectangle(cornerRadius: CornerRadius.tag)
                    .strokeBorder(.primary.opacity(0.55), lineWidth: 1)
            }
    }
}

/// Marks something picked since the shuffle that plays from the next one.
public struct AccentTag: View {
    private let text: String

    @Environment(\.backgroundProminence) private var prominence

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        let isOnSelection = prominence == .increased
        TagText(text)
            .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(.accentText))
            .background(
                isOnSelection ? AnyShapeStyle(.primary.opacity(0.2)) : AnyShapeStyle(.accentText.opacity(0.14)),
                in: .rect(cornerRadius: CornerRadius.tag)
            )
    }
}

/// The speaker beside the song that's playing now.
public struct NowPlayingGlyph: View {
    @Environment(\.backgroundProminence) private var prominence

    public init() {}

    public var body: some View {
        Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.accentText))
            .accessibilityLabel("Playing now")
    }
}

/// A list column's heading, laid out by `ListColumns` like the rows below it.
public struct ColumnLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.columnLabel)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

/// A column heading that sorts the list. The sorted column reads in full ink with a chevron.
public struct ColumnSortButtonStyle: ButtonStyle {
    private let isSorted: Bool

    public init(isSorted: Bool) {
        self.isSorted = isSorted
    }

    public func makeBody(configuration: Configuration) -> some View {
        ColumnSortLabel(isSorted: isSorted, isPressed: configuration.isPressed) { configuration.label }
    }
}

private struct ColumnSortLabel<Label: View>: View {
    let isSorted: Bool
    let isPressed: Bool
    @ViewBuilder let label: Label

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.s2) {
            label
            if isSorted {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
        }
        .font(.columnLabel)
        .foregroundStyle(isSorted || isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .lineLimit(1)
        .opacity(isPressed ? 0.6 : 1)
        .contentShape(.rect)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSorted ? .isSelected : [])
    }
}

extension ButtonStyle where Self == ColumnSortButtonStyle {
    public static func columnSort(isSorted: Bool) -> ColumnSortButtonStyle {
        .init(isSorted: isSorted)
    }
}

private struct TagText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.tag)
            .lineLimit(1)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, 1)
    }
}

public struct SectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.sectionTitle)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A dark capsule of icon buttons, such as Settings above the player.
public struct PillToolbar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            content
        }
        .buttonStyle(.pillIcon)
        .padding(.horizontal, Spacing.s4)
        .frame(height: 32)
        .background(.chrome, in: .capsule)
        .overlay { Capsule().strokeBorder(.white.opacity(0.08)) }
        .elevation(.pill)
    }
}
