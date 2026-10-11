import SwiftUI

/// The top of an artist or playlist: its artwork, name and a count, with the actions for all of it.
public struct CollectionHeader<Artwork: View, Actions: View>: View {
    private let title: String
    private let subtitle: String
    private let artwork: Artwork
    private let actions: Actions

    public init(
        _ title: String,
        subtitle: String,
        @ViewBuilder artwork: () -> Artwork,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork()
        self.actions = actions()
    }

    public var body: some View {
        HStack(spacing: Spacing.s16) {
            artwork
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text(title)
                    .font(.collectionTitle)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.bodyText.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: Spacing.s16)
            actions
        }
        .padding(.vertical, 18)
        .padding(.horizontal, Spacing.s20)
        .overlay(alignment: .bottom) { Rectangle().fill(.hairline).frame(height: 1) }
    }
}
