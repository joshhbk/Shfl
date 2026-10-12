import SwiftUI

/// A menu's label drawn as a filled field with up and down chevrons. Pair with `.menuStyle(.button)`
/// and `.buttonStyle(.plain)`.
public struct FieldLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        HStack(spacing: Spacing.s8) {
            Text(title)
                .font(.bodyEmphasis)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, Spacing.s12)
        .padding(.trailing, Spacing.s8)
        .frame(height: 32)
        .background(.quietFill, in: .rect(cornerRadius: CornerRadius.regular))
        .contentShape(.rect(cornerRadius: CornerRadius.regular))
    }
}

/// A label and a short value on one line, such as "Next shuffle · Picks have changed".
public struct StatusLine<Value: View>: View {
    private let label: String
    private let value: Value

    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
            Text(label)
                .font(.statusLabel)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            value
                .font(.statusLine)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Rings a field whose value differs from what's in use.
    public func fieldHighlight(_ isHighlighted: Bool) -> some View {
        overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: CornerRadius.regular).strokeBorder(.accentText, lineWidth: 1.5)
            }
        }
    }
}
