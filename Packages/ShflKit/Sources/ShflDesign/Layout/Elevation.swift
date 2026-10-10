import SwiftUI

public struct Elevation: Hashable, Sendable {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat

    /// SwiftUI's radius is roughly half a CSS blur, so values here are the canvas's blur halved.
    init(opacity: Double, cssBlur: CGFloat, y: CGFloat) {
        self.opacity = opacity
        self.radius = cssBlur / 2
        self.y = y
    }

    public static let artworkLarge = Elevation(opacity: 0.28, cssBlur: 28, y: 10)
    public static let artworkSmall = Elevation(opacity: 0.30, cssBlur: 12, y: 4)
    public static let wheel = Elevation(opacity: 0.28, cssBlur: 26, y: 10)
    public static let pill = Elevation(opacity: 0.20, cssBlur: 8, y: 2)
    public static let notice = Elevation(opacity: 0.12, cssBlur: 20, y: 6)
    public static let menu = Elevation(opacity: 0.10, cssBlur: 24, y: 8)
    public static let floatingBar = Elevation(opacity: 0.22, cssBlur: 32, y: 10)
    public static let popover = Elevation(opacity: 0.30, cssBlur: 56, y: 22)
    public static let window = Elevation(opacity: 0.35, cssBlur: 60, y: 24)
}

extension View {
    public func elevation(_ elevation: Elevation) -> some View {
        shadow(color: .black.opacity(elevation.opacity), radius: elevation.radius, y: elevation.y)
    }
}
