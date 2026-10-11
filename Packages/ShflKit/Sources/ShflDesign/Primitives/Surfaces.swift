import SwiftUI

/// Each surface sets the hierarchical foreground styles, so primitives that draw in `.primary` and
/// `.secondary` pick up ink on the player and neutral text everywhere else.
extension View {
    public func playerSurface() -> some View {
        foregroundStyle(.ink, .inkSecondary)
            .background(.playerBody)
    }

    public func contentSurface() -> some View {
        foregroundStyle(.textPrimary, .textSecondary, .textTertiary)
            .background(.surfaceContent)
    }

    public func paneSurface() -> some View {
        foregroundStyle(.textPrimary, .textSecondary, .textTertiary)
            .background(.surfacePane)
    }

    public func elevatedSurface() -> some View {
        foregroundStyle(.textPrimary, .textSecondary, .textTertiary)
            .background(.surfaceElevated)
    }
}
