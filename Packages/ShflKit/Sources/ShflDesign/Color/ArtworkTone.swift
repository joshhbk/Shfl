import SwiftUI

public nonisolated enum ArtworkTone {
    /// The artwork's darkest strong colour, or nil when it has only greys.
    public static func pick(from colors: [Color.Resolved]) -> Color.Resolved? {
        colors
            .filter { ColorMath.chroma($0) >= minimumChroma }
            .min { ColorMath.luminance($0) < ColorMath.luminance($1) }
    }

    static let minimumChroma: Float = 0.04
}
