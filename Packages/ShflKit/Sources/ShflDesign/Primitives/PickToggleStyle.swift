import SwiftUI

/// A row's pick: an outlined plus when off, a filled tick when on, a dashed plus when there's no room.
/// The label is read by VoiceOver, never drawn.
public struct PickToggleStyle: ToggleStyle {
    public func makeBody(configuration: Configuration) -> some View {
        PickCircle(isOn: configuration.isOn) { configuration.isOn.toggle() }
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
    }
}

private struct PickCircle: View {
    let isOn: Bool
    let toggle: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    static let diameter: CGFloat = 24

    var body: some View {
        Button(action: toggle) {
            Image(systemName: isOn ? "checkmark" : "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isOn ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.secondary))
                .frame(width: Self.diameter, height: Self.diameter)
                .background(isOn ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.clear), in: .circle)
                .overlay {
                    Circle().strokeBorder(
                        isOn ? DesignColor(role: .selectable(.accent, selectedOpacity: 1)) : .textTertiary,
                        style: StrokeStyle(lineWidth: 1.5, dash: isEnabled || isOn ? [] : [3, 2])
                    )
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.7)
    }
}

extension ToggleStyle where Self == PickToggleStyle {
    public static var pick: PickToggleStyle { .init() }
}
