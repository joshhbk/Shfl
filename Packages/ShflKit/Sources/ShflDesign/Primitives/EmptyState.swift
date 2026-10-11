import SwiftUI

/// What a list says when it has nothing to show, with quiet buttons for the way out.
public struct EmptyState<Symbol: View, Actions: View>: View {
    private let title: String
    private let message: String
    private let symbol: Symbol
    private let actions: Actions

    public init(
        _ title: String,
        message: String,
        @ViewBuilder symbol: () -> Symbol,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.message = message
        self.symbol = symbol()
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: Spacing.s6) {
            symbol
                .padding(.bottom, Spacing.s6)
            Text(title)
                .font(.emptyStateTitle)
                .foregroundStyle(.primary)
            Text(message)
                .font(.secondaryText)
                .foregroundStyle(.secondary)
            HStack(spacing: Spacing.s8) {
                actions
            }
            .buttonStyle(.quiet)
            .controlSize(.small)
            .padding(.top, Spacing.s8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(.horizontal, Spacing.s20)
    }
}

extension EmptyState where Symbol == EmptyView {
    public init(_ title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.init(title, message: message, symbol: { EmptyView() }, actions: actions)
    }
}

/// The rounded tile above an `EmptyState`'s title.
public struct EmptyStateSymbol: View {
    private let systemImage: String

    public init(_ systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 24, weight: .regular))
            .foregroundStyle(.tertiary)
            .frame(width: 52, height: 52)
            .background(.quietFill, in: .rect(cornerRadius: CornerRadius.card))
            .accessibilityHidden(true)
    }
}
