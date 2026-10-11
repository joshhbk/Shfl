import SwiftUI

nonisolated extension EnvironmentValues {
    @Entry public var shflTheme: ShflTheme = .pink
    @Entry public var artworkTone: Color.Resolved? = nil
}

extension View {
    public func shflTheme(_ theme: ShflTheme) -> some View {
        environment(\.shflTheme, theme)
    }

    /// Tints `.playerBody` with the artwork's darkest strong colour; pass nil when there's no artwork.
    public func artworkTint(_ tone: Color.Resolved?) -> some View {
        environment(\.artworkTone, tone)
    }
}
