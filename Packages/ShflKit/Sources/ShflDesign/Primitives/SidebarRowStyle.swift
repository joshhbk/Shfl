import SwiftUI

/// A sidebar row from a `Label`: the selected row is a solid block of the theme colour, the others carry
/// a theme-coloured icon.
public struct SidebarRowStyle: ButtonStyle {
    private let isSelected: Bool

    public init(isSelected: Bool) {
        self.isSelected = isSelected
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(SidebarRowLabelStyle(isSelected: isSelected))
            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.primary))
            .padding(.horizontal, Spacing.s10)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.clear), in: .rect(cornerRadius: CornerRadius.regular))
            .contentShape(.rect(cornerRadius: CornerRadius.regular))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct SidebarRowLabelStyle: LabelStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Spacing.s10) {
            configuration.icon
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isSelected ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.accentText))
                .frame(width: 20)
            configuration.title
        }
    }
}

extension ButtonStyle where Self == SidebarRowStyle {
    public static func sidebarRow(isSelected: Bool) -> SidebarRowStyle {
        .init(isSelected: isSelected)
    }
}
