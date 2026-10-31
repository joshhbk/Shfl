import SwiftUI

enum PicksLayout: String {
    case tray
    case list
}

extension FocusedValues {
    @Entry var picksLayout: Binding<PicksLayout>?
}
