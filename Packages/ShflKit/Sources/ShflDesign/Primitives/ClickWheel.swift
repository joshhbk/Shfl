import SwiftUI

enum ClickWheelMetrics {
    static let diameter: CGFloat = 184
    static let centerDiameter: CGFloat = 96
    static let edgeInset: CGFloat = 10
}

public enum ClickWheelSlot: Hashable, Sendable {
    case center, top, leading, trailing, bottom

    func moved(_ direction: KeyEquivalent) -> ClickWheelSlot {
        switch (direction, self) {
        case (.upArrow, .bottom), (.downArrow, .top), (.leftArrow, .trailing), (.rightArrow, .leading): .center
        case (.upArrow, _): .top
        case (.downArrow, _): .bottom
        case (.leftArrow, _): .leading
        case (.rightArrow, _): .trailing
        default: self
        }
    }
}

/// The click wheel's layout and look. It knows nothing about playback: the caller puts a button in
/// each slot and the wheel styles them, edge slots with `.wheel` and the centre with `.wheelCenter`.
///
/// The wheel is one keyboard stop: arrow keys pick a slot and Space or Return calls `onKeyboardPress`.
public struct ClickWheel<Center: View, Top: View, Leading: View, Trailing: View, Bottom: View>: View {
    private let center: Center
    private let top: Top
    private let leading: Leading
    private let trailing: Trailing
    private let bottom: Bottom
    private let onKeyboardPress: (ClickWheelSlot) -> Void

    @FocusState private var isFocused: Bool
    @State private var highlighted = ClickWheelSlot.center

    public init(
        onKeyboardPress: @escaping (ClickWheelSlot) -> Void,
        @ViewBuilder center: () -> Center,
        @ViewBuilder top: () -> Top,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.onKeyboardPress = onKeyboardPress
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
                slot(.top) { top }
                Spacer()
                slot(.bottom) { bottom }
            }
            .padding(.vertical, ClickWheelMetrics.edgeInset)
            HStack {
                slot(.leading) { leading }
                Spacer()
                slot(.trailing) { trailing }
            }
            .padding(.horizontal, ClickWheelMetrics.edgeInset)
            slot(.center) { center.buttonStyle(.wheelCenter) }
        }
        .buttonStyle(.wheel)
        .toggleStyle(.wheel)
        .frame(width: ClickWheelMetrics.diameter, height: ClickWheelMetrics.diameter)
        // .activate takes focus only under Keyboard Navigation, so a click doesn't leave the ring behind.
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            highlighted = highlighted.moved(press.key)
            return .handled
        }
        .onKeyPress(keys: [.space, .return]) { _ in
            onKeyboardPress(highlighted)
            return .handled
        }
        .accessibilityElement(children: .contain)
    }

    private func slot(_ slot: ClickWheelSlot, @ViewBuilder content: () -> some View) -> some View {
        content()
            .focusable(false)
            .overlay {
                if isFocused && highlighted == slot {
                    FocusRing(isCircle: slot == .center)
                }
            }
    }
}

private struct FocusRing: View {
    let isCircle: Bool

    var body: some View {
        Group {
            if isCircle {
                Circle().strokeBorder(.accentText, lineWidth: 3)
                    .padding(-3)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.regular).strokeBorder(.accentText, lineWidth: 3)
                    .padding(-3)
            }
        }
        .allowsHitTesting(false)
    }
}
