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

/// `ArtworkFrame` for people: a circle, for artists.
public struct RoundArtworkFrame<Content: View>: View {
    private let size: CGFloat
    private let content: Content

    public init(size: CGFloat, @ViewBuilder content: () -> Content) {
        self.size = size
        self.content = content()
    }

    public var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(.gray.opacity(0.28), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// A name's first letter on a colour picked from the name, for artists without artwork.
public struct MonogramArtwork: View {
    private let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var body: some View {
        GeometryReader { geometry in
            Text(Self.initial(of: name))
                .font(.system(size: geometry.size.width * 0.4, weight: .heavy, design: .rounded))
                .foregroundStyle(.onAccent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(Self.tone(for: name)))
    }

    static func initial(of name: String) -> String {
        name.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "♪"
    }

    static func tone(for name: String) -> Color.Resolved {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Palette.monograms[sum % Palette.monograms.count]
    }
}
