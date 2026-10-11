import SwiftUI

/// A 40pt list row for Up Next, the whole session and the pool list. Compose it from
/// `RowIndex`, an `ArtworkFrame`, `RowTitles` and `RowDetail` or a tag.
public struct CompactRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Spacing.s10) {
            content
        }
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }
}

public struct RowIndex: View {
    private let position: Int

    public init(_ position: Int) {
        self.position = position
    }

    public var body: some View {
        Text(position, format: .number)
            .font(.meta.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 18, alignment: .trailing)
    }
}

public struct RowTitles: View {
    private let title: String
    private let subtitle: String

    public init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.rowTitle)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.meta)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Trailing metadata such as a duration.
public struct RowDetail: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.meta.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

extension View {
    /// Marks the row that's playing now.
    public func rowHighlight(_ isHighlighted: Bool) -> some View {
        padding(.horizontal, Spacing.s8)
            .background(.primary.opacity(isHighlighted ? 0.16 : 0), in: .rect(cornerRadius: CornerRadius.regular))
            .padding(.horizontal, -Spacing.s8)
    }
}
