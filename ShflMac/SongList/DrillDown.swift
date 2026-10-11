import SwiftUI

extension View {
    /// Shows `detail` over this view while `item` is set. Not a NavigationStack: pages pushed on one lose the
    /// detail column's inspector, toolbar and environment. The list underneath keeps its scroll position.
    func drillDown<Item: Identifiable, Detail: View>(
        item: Binding<Item?>,
        @ViewBuilder detail: @escaping (Item) -> Detail
    ) -> some View {
        modifier(DrillDownModifier(item: item, detail: detail))
    }
}

private struct DrillDownModifier<Item: Identifiable, Detail: View>: ViewModifier {
    @Binding var item: Item?
    let detail: (Item) -> Detail

    func body(content: Content) -> some View {
        ZStack {
            content
                .opacity(item == nil ? 1 : 0)
                .disabled(item != nil)
                .accessibilityHidden(item != nil)
            if let item {
                detail(item)
                    .id(item.id)
                    .environment(\.goBack, GoBackAction { self.item = nil })
            }
        }
    }
}

struct GoBackAction {
    private let back: () -> Void

    init(_ back: @escaping () -> Void) {
        self.back = back
    }

    func callAsFunction() {
        back()
    }
}

extension EnvironmentValues {
    @Entry var goBack: GoBackAction?
}
