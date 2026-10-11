import SwiftUI

/// Marks something that applies from the next shuffle.
public struct SoftTag: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        TagText(text)
            .foregroundStyle(.accentText)
            .background(.accentSoft, in: .rect(cornerRadius: CornerRadius.tag))
    }
}

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

public struct SectionHeader<Detail: View>: View {
    private let title: String
    private let detail: Detail

    public init(_ title: String, @ViewBuilder detail: () -> Detail) {
        self.title = title
        self.detail = detail()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            detail
                .font(.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

extension SectionHeader where Detail == EmptyView {
    public init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

public struct EmptyState<Actions: View>: View {
    private let title: String
    private let message: String
    private let actions: Actions

    public init(_ title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Spacing.s6) {
            Text(title)
                .font(.emptyStateTitle)
                .foregroundStyle(.primary)
            Text(message)
                .font(.secondaryText)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.s8) {
                actions
            }
            .controlSize(.small)
            .padding(.top, Spacing.s8)
        }
        .multilineTextAlignment(.center)
    }
}

extension EmptyState where Actions == EmptyView {
    public init(_ title: String, message: String) {
        self.init(title, message: message) { EmptyView() }
    }
}

/// A dark capsule of icon buttons, such as Mini Player and Settings above the player.
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
