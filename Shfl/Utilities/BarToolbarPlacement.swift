import SwiftUI

extension ToolbarItemPlacement {
    /// Leading edge of the navigation bar on iOS; the window toolbar's
    /// navigation area on macOS.
    static var barLeading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    /// Trailing edge of the navigation bar on iOS; the window toolbar's
    /// primary action area on macOS.
    static var barTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }
}
