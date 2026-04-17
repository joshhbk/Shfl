import SwiftUI

struct PickerHeaderStyle: Equatable {
    let background: Color
    let pillBackground: Color
    let toolbarColorScheme: ColorScheme?
    let primaryContent: Color
    let secondaryContent: Color
    let disabledContent: Color
    let ringTrack: Color
    let ringFill: Color

    var isTinted: Bool { toolbarColorScheme != nil }

    static func resolve(theme: ShuffleTheme, colorScheme: ColorScheme) -> PickerHeaderStyle {
        guard colorScheme == .light else {
            return .systemDefault
        }

        let isLightBackground = theme.textStyle == .dark
        return PickerHeaderStyle(
            background: theme.bodyGradientTop,
            pillBackground: ColorBlending.darken(theme.bodyGradientTop, by: 0.22),
            toolbarColorScheme: isLightBackground ? .light : .dark,
            primaryContent: theme.textColor,
            secondaryContent: theme.secondaryTextColor,
            disabledContent: theme.textColor.opacity(0.5),
            ringTrack: theme.textColor.opacity(0.22),
            ringFill: theme.textColor
        )
    }

    static let systemDefault = PickerHeaderStyle(
        background: Color(.systemGroupedBackground),
        pillBackground: Color(.systemFill),
        toolbarColorScheme: nil,
        primaryContent: .primary,
        secondaryContent: .secondary,
        disabledContent: .secondary,
        ringTrack: Color(.systemFill),
        ringFill: .accentColor
    )
}
