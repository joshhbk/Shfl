import SwiftUI

/// A bar that floats over the bottom of a list, like the selection bar. Lead with a count, then the actions.
public struct FloatingBar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: Spacing.s12) {
            content
        }
        .font(.sectionTitle)
        .controlSize(.small)
        .lineLimit(1)
        .padding(.vertical, Spacing.s8)
        .padding(.leading, Spacing.s16)
        .padding(.trailing, Spacing.s8)
        .elevatedSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.floating))
        .overlay { RoundedRectangle(cornerRadius: CornerRadius.floating).strokeBorder(.hairline) }
        .elevation(.floating)
    }
}

/// The key that triggers a button, shown inside it: "Add to Picks ↩".
public struct KeyHint: View {
    private let key: String

    public init(_ key: String) {
        self.key = key
    }

    public var body: some View {
        Text(key)
            .font(.keyHint)
            .padding(.horizontal, Spacing.s6)
            .padding(.vertical, 3)
            .background(.onAccent.opacity(0.2), in: .rect(cornerRadius: CornerRadius.tag))
            .accessibilityHidden(true)
    }
}
