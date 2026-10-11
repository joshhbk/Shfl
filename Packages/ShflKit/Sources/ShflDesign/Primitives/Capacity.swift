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

/// A slim bar filled to `count`, with ticks and labels at `marks`.
public struct CapacityRule: View {
    private let count: Int
    private let total: Int
    private let marks: [Int]

    public init(_ count: Int, of total: Int, marks: [Int]) {
        self.count = count
        self.total = total
        self.marks = marks
    }

    public var body: some View {
        VStack(spacing: Spacing.s4) {
            Capsule()
                .fill(.traySlot)
                .frame(height: 8)
                .overlay { GeometryReader { bar(width: $0.size.width) } }
            GeometryReader { labels(width: $0.size.width) }
                .frame(height: 14)
        }
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(.accentFill)
                .frame(width: width * fraction(of: count))
            ForEach(marks.filter { $0 < total }, id: \.self) { mark in
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 1.5, height: 14)
                    .offset(x: width * fraction(of: mark))
            }
        }
        .frame(width: width, height: 8, alignment: .leading)
    }

    private func labels(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Pins the stack's leading edge at zero, so the guides below place each label from there.
            Color.clear.frame(width: width, height: 1)
            ForEach(marks, id: \.self) { mark in
                Text(mark, format: .number)
                    .font(.rulerMark.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .alignmentGuide(.leading) { label in
                        mark < total ? label.width / 2 - width * fraction(of: mark) : label.width - width
                    }
            }
        }
        .frame(width: width, alignment: .topLeading)
    }

    private func fraction(of value: Int) -> CGFloat {
        total > 0 ? CGFloat(min(value, total)) / CGFloat(total) : 0
    }
}
