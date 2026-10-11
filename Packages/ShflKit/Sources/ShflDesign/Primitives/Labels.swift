import SwiftUI

/// Marks something that no longer matches the pool but still plays this session.
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
