import SwiftUI

/// A thin position track drawn in the surface's primary style. Mirrors `Slider`: the binding moves
/// while dragging, and `onEditingChanged(false)` marks the moment to commit.
public struct Scrubber: View {
    @Binding private var value: Double
    private let bounds: ClosedRange<Double>
    private let step: Double
    private let onEditingChanged: (Bool) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isDragging = false

    public init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _value = value
        self.bounds = bounds
        self.step = step
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            let fraction = Self.fraction(of: value, in: bounds)
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.28))
                Capsule().fill(.primary)
                    .frame(width: geometry.size.width * fraction)
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(drag(width: geometry.size.width), isEnabled: isEnabled)
        }
        .frame(height: 16)
        .focusable(isEnabled)
        .onKeyPress(.leftArrow) { nudge(by: -step) }
        .onKeyPress(.rightArrow) { nudge(by: step) }
        .accessibilityRepresentation {
            Slider(value: $value, in: bounds, step: step, onEditingChanged: onEditingChanged)
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                    onEditingChanged(true)
                }
                value = Self.value(at: gesture.location.x, width: width, in: bounds)
            }
            .onEnded { _ in
                isDragging = false
                onEditingChanged(false)
            }
    }

    private func nudge(by delta: Double) -> KeyPress.Result {
        value = min(max(value + delta, bounds.lowerBound), bounds.upperBound)
        onEditingChanged(false)
        return .handled
    }

    static func fraction(of value: Double, in bounds: ClosedRange<Double>) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(max((value - bounds.lowerBound) / span, 0), 1))
    }

    static func value(at x: CGFloat, width: CGFloat, in bounds: ClosedRange<Double>) -> Double {
        guard width > 0 else { return bounds.lowerBound }
        let fraction = Double(min(max(x / width, 0), 1))
        return bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound)
    }
}
