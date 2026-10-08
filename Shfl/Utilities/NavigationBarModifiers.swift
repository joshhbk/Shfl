import SwiftUI

extension View {
    /// Shows the navigation title inline on iOS. Mac windows always show the
    /// title in the toolbar, so there's nothing to change there.
    func inlineNavigationTitle() -> some View {
        #if os(macOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension View {
    /// Gives the iOS navigation bar a solid grouped background. Mac window
    /// toolbars draw their own material, so nothing changes there.
    func groupedNavigationBarBackground() -> some View {
        #if os(macOS)
        self
        #else
        toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.groupedBackground, for: .navigationBar)
        #endif
    }
}
