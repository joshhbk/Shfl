import SwiftUI

enum ClickWheelMetrics {
    static let diameter: CGFloat = 184
    static let centerDiameter: CGFloat = 96
    static let edgeInset: CGFloat = 10
}

/// The click wheel's layout and look. It knows nothing about playback: the caller puts a button in
/// each slot and the wheel styles them, edge slots with `.wheel` and the centre with `.wheelCenter`.
public struct ClickWheel<Center: View, Top: View, Leading: View, Trailing: View, Bottom: View>: View {
    private let center: Center
    private let top: Top
    private let leading: Leading
    private let trailing: Trailing
    private let bottom: Bottom

    public init(
        @ViewBuilder center: () -> Center,
        @ViewBuilder top: () -> Top,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.center = center()
        self.top = top()
        self.leading = leading()
        self.trailing = trailing()
        self.bottom = bottom()
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(.wheel)
                .overlay { Circle().strokeBorder(.white.opacity(0.07)) }
                .elevation(.wheel)
            VStack {
                top
                Spacer()
                bottom
            }
            .padding(.vertical, ClickWheelMetrics.edgeInset)
            HStack {
                leading
                Spacer()
                trailing
            }
            .padding(.horizontal, ClickWheelMetrics.edgeInset)
            center
                .buttonStyle(.wheelCenter)
        }
        .buttonStyle(.wheel)
        .toggleStyle(.wheel)
        .frame(width: ClickWheelMetrics.diameter, height: ClickWheelMetrics.diameter)
        .accessibilityElement(children: .contain)
    }
}
