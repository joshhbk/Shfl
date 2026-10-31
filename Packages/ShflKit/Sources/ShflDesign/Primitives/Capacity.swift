import SwiftUI

/// A big rounded count over its limit: "86 / 120".
public struct CountFraction: View {
    private let count: Int
    private let total: Int

    public init(_ count: Int, of total: Int) {
        self.count = count
        self.total = total
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
            Text(count, format: .number)
                .font(.countLarge.monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText(value: Double(count)))
            Text("/ \(total)")
                .font(.countUnit.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(total)")
    }
}
