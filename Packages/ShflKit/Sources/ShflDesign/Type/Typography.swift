import SwiftUI

/// Type roles from the design canvas. Rounded is for counts, headings and buttons; song titles stay in SF Pro.
/// Counts and times also take `.monospacedDigit()`.
extension Font {
    public static let display = Font.system(size: 42, weight: .heavy, design: .rounded)
    public static let heading = Font.system(size: 22, weight: .heavy, design: .rounded)
    public static let count = Font.system(size: 46, weight: .heavy, design: .rounded)
    public static let countSuffix = Font.system(size: 20, weight: .bold, design: .rounded)
    public static let cardTitle = Font.system(size: 14, weight: .heavy, design: .rounded)
    public static let emptyStateTitle = Font.system(size: 16, weight: .bold, design: .rounded)

    public static let playerTitle = Font.system(size: 20, weight: .bold)
    public static let playerTitleCompact = Font.system(size: 17, weight: .bold)

    public static let paneTitle = Font.system(size: 15, weight: .semibold)
    public static let sectionTitle = Font.system(size: 13, weight: .semibold)
    public static let bodyText = Font.system(size: 13)
    public static let bodyEmphasis = Font.system(size: 13, weight: .medium)
    public static let secondaryText = Font.system(size: 12)
    public static let rowTitle = Font.system(size: 12, weight: .medium)
    public static let meta = Font.system(size: 11)
    public static let columnLabel = Font.system(size: 11, weight: .semibold)
    public static let tag = Font.system(size: 10.5, weight: .semibold)

    /// For 28–32pt-tall buttons.
    public static let buttonSmall = Font.system(size: 13, weight: .bold, design: .rounded)
    /// For 38pt-tall buttons.
    public static let buttonRegular = Font.system(size: 14, weight: .bold, design: .rounded)
    /// For 44pt-tall buttons.
    public static let buttonLarge = Font.system(size: 15, weight: .bold, design: .rounded)
    public static let quietButton = Font.system(size: 12, weight: .medium)
}
