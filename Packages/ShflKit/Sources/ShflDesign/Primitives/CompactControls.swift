import SwiftUI

/// Previous and Next outside the wheel, e.g. in the menu bar player.
public struct TransportButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.ink)
            .frame(width: 40, height: 36)
            .background(.ink.opacity(configuration.isPressed ? 0.14 : 0), in: .rect(cornerRadius: CornerRadius.panel))
            .contentShape(.rect(cornerRadius: CornerRadius.panel))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Play or Pause outside the wheel: ink on the body, the inverse of its surroundings like the wheel's centre.
public struct TransportPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.playerBody)
            .frame(width: 44, height: 44)
            .background(.ink, in: .rect(cornerRadius: CornerRadius.card))
            .contentShape(.rect(cornerRadius: CornerRadius.card))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A full-width row in a popover's menu list that highlights under the pointer.
public struct MenuRowButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        MenuRow(isPressed: configuration.isPressed) { configuration.label }
    }
}

private struct MenuRow<Label: View>: View {
    let isPressed: Bool
    @ViewBuilder let label: Label

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        label
            .font(.bodyText)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.horizontal, Spacing.s10)
            .background(.quietFill.opacity(isHovered || isPressed ? 1 : 0), in: .rect(cornerRadius: CornerRadius.control))
            .contentShape(.rect)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == TransportButtonStyle {
    public static var transport: TransportButtonStyle { .init() }
}

extension ButtonStyle where Self == TransportPrimaryButtonStyle {
    public static var transportPrimary: TransportPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == MenuRowButtonStyle {
    public static var menuRow: MenuRowButtonStyle { .init() }
}
