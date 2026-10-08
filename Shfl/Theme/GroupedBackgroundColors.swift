import SwiftUI

extension Color {
    /// The grouped-list background: `systemGroupedBackground` on iOS, the
    /// window background on macOS.
    static var groupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemGroupedBackground)
        #endif
    }

    /// Cells and fields sitting on a `groupedBackground`.
    static var secondaryGroupedBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(.secondarySystemGroupedBackground)
        #endif
    }
}
