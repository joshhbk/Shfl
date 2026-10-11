import SwiftUI

/// Moves the main window to another sidebar place, like Search Artists from an empty song search.
struct ShowPlaceAction {
    private let show: (SidebarItem) -> Void

    init(_ show: @escaping (SidebarItem) -> Void) {
        self.show = show
    }

    func callAsFunction(_ place: SidebarItem) {
        show(place)
    }
}

extension EnvironmentValues {
    @Entry var showPlace = ShowPlaceAction { _ in }
}
