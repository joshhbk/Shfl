import SwiftUI

/// Sizes, rounds and edges whatever artwork the caller supplies. Shadows are the caller's choice.
public struct ArtworkFrame<Content: View>: View {
    private let size: CGFloat
    private let content: Content

    public init(size: CGFloat, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius(for: size))
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.gray.opacity(0.28), lineWidth: 1) }
            .accessibilityHidden(true)
    }

    static func cornerRadius(for size: CGFloat) -> CGFloat {
        switch size {
        case 168...: CornerRadius.card
        case 56...: CornerRadius.regular
        case 34...: CornerRadius.tag
        default: CornerRadius.tile
        }
    }
}

/// What an `ArtworkFrame` shows when there's no artwork, or for a state like Finished.
public struct ArtworkPlaceholder: View {
    private let systemImage: String

    public init(systemImage: String = "music.note") {
        self.systemImage = systemImage
    }

    public var body: some View {
        GeometryReader { geometry in
            Image(systemName: systemImage)
                .font(.system(size: geometry.size.width * 0.34, weight: .regular))
                .foregroundStyle(.artworkPlaceholderGlyph)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.artworkPlaceholder)
    }
}
