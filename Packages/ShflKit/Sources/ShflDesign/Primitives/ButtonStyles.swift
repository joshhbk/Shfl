import SwiftUI

/// Height, type and corner radius for text buttons, chosen with `.controlSize(_:)`.
struct TextButtonMetrics {
    let height: CGFloat
    let radius: CGFloat
    let font: Font

    init(_ size: ControlSize) {
        switch size {
        case .mini, .small:
            self.init(height: 30, radius: CornerRadius.regular, font: .buttonSmall)
        case .large, .extraLarge:
            self.init(height: 44, radius: CornerRadius.card, font: .buttonLarge)
        default:
            self.init(height: 38, radius: CornerRadius.panel, font: .buttonRegular)
        }
    }

    private init(height: CGFloat, radius: CGFloat, font: Font) {
        self.height = height
        self.radius = radius
        self.font = font
    }
}

/// The one action a pane leads with: Shuffle Now, Add to Pool.
public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        let metrics = TextButtonMetrics(controlSize)
        configuration.label
            .font(metrics.font)
            .foregroundStyle(.onAccent)
            .padding(.horizontal, Spacing.s16)
            .frame(minHeight: metrics.height)
            .background(.accentFill, in: .rect(cornerRadius: metrics.radius))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect(cornerRadius: metrics.radius))
    }
}

/// The same action when it isn't the pane's lead, e.g. Shuffle Again when nothing has changed.
public struct OutlineButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        let metrics = TextButtonMetrics(controlSize)
        configuration.label
            .font(metrics.font)
            .foregroundStyle(.accentText)
            .padding(.horizontal, Spacing.s16)
            .frame(minHeight: metrics.height)
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius).strokeBorder(.accentText, lineWidth: 1.5)
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.rect(cornerRadius: metrics.radius))
    }
}

/// Secondary actions such as Autofill, Clear and Deselect.
public struct QuietButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        let isSmall = controlSize == .mini || controlSize == .small
        configuration.label
            .font(isSmall ? .quietButton : .bodyEmphasis)
            .foregroundStyle(.primary)
            .padding(.horizontal, Spacing.s12)
            .frame(minHeight: isSmall ? 28 : 30)
            .background(.quietFill, in: .rect(cornerRadius: isSmall ? CornerRadius.control : CornerRadius.regular))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Icon buttons inside a `PillToolbar`.
public struct PillIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.chromeGlyph)
            .frame(width: 32, height: 28)
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0), in: .capsule)
            .contentShape(.capsule)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// The wheel's four edge buttons.
public struct WheelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        WheelGlyph(isPressed: configuration.isPressed, isOn: false, isEnabled: isEnabled) {
            configuration.label
        }
    }
}

/// The wheel's centre: the theme body with an ink glyph, the inverse of the dark wheel around it.
public struct WheelCenterButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.ink)
            .frame(width: ClickWheelMetrics.centerDiameter, height: ClickWheelMetrics.centerDiameter)
            .background(.playerBody, in: .circle)
            .contentShape(.circle)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// An edge of the wheel that shows a mode, like the whole session.
public struct WheelToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            WheelGlyph(isPressed: false, isOn: configuration.isOn, isEnabled: isEnabled) {
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

private struct WheelGlyph<Label: View>: View {
    let isPressed: Bool
    let isOn: Bool
    let isEnabled: Bool
    @ViewBuilder let label: Label

    var body: some View {
        label
            .labelStyle(.iconOnly)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.wheelGlyph)
            .frame(width: 36, height: 32)
            .background(.wheelGlyph.opacity(isOn ? 0.22 : 0), in: .rect(cornerRadius: CornerRadius.regular))
            .contentShape(.rect)
            .opacity(isPressed ? 0.6 : 1)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    public static var primary: PrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == OutlineButtonStyle {
    public static var outline: OutlineButtonStyle { .init() }
}

extension ButtonStyle where Self == QuietButtonStyle {
    public static var quiet: QuietButtonStyle { .init() }
}

extension ButtonStyle where Self == PillIconButtonStyle {
    public static var pillIcon: PillIconButtonStyle { .init() }
}

extension ButtonStyle where Self == WheelButtonStyle {
    public static var wheel: WheelButtonStyle { .init() }
}

extension ButtonStyle where Self == WheelCenterButtonStyle {
    public static var wheelCenter: WheelCenterButtonStyle { .init() }
}

extension ToggleStyle where Self == WheelToggleStyle {
    public static var wheel: WheelToggleStyle { .init() }
}
