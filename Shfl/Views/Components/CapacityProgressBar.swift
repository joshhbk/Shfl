import SwiftUI

// MARK: - Shared Modifier

private struct CapacityPulseModifier: ViewModifier {
    let current: Int
    let maximum: Int
    @Binding var pulseOpacity: Double

    func body(content: Content) -> some View {
        content
            .onChange(of: current) { oldValue, newValue in
                if CapacityProgressBar.shouldCelebrate(previous: oldValue, current: newValue, maximum: maximum) {
                    HapticFeedback.success.trigger()
                }

                if newValue > oldValue && newValue > 0 {
                    HapticFeedback.light.trigger()
                    withAnimation(.easeIn(duration: 0.1)) {
                        pulseOpacity = 1
                    }
                    withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                        pulseOpacity = 0
                    }
                }
            }
    }
}

struct CapacityProgressBar: View {
    let current: Int
    let maximum: Int

    @State private var pulseOpacity: Double = 0

    private var progress: Double {
        Self.calculateProgress(current: current, maximum: maximum)
    }

    private var isFull: Bool {
        current >= maximum
    }

    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    // Fill - skip animation when clearing to zero
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isFull ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * progress)
                        .brightness(pulseOpacity * 0.3)
                        .animation(progress == 0 ? nil : .spring(response: 0.35, dampingFraction: 0.65), value: progress)
                }
            }
            .frame(height: 6)

            Text("\(current) / \(maximum)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isFull ? .green : .secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
        .modifier(CapacityPulseModifier(current: current, maximum: maximum, pulseOpacity: $pulseOpacity))
    }

    // MARK: - Static Helpers (for testing)

    static func calculateProgress(current: Int, maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return Double(current) / Double(maximum)
    }

    static func isMilestone(_ count: Int) -> Bool {
        [1, 50, 100, 120].contains(count)
    }

    static func shouldCelebrate(previous: Int, current: Int, maximum: Int) -> Bool {
        let wasNotFull = previous < maximum
        let isNowFull = current >= maximum
        return wasNotFull && isNowFull
    }
}

struct CompactCapacityBar: View {
    let current: Int
    let maximum: Int

    @State private var pulseOpacity: Double = 0

    private var progress: Double {
        CapacityProgressBar.calculateProgress(current: current, maximum: maximum)
    }

    private var isFull: Bool {
        current >= maximum
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemFill))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(isFull ? Color.green : Color.accentColor)
                        .frame(width: geometry.size.width * progress)
                        .brightness(pulseOpacity * 0.3)
                        .animation(
                            progress == 0 ? nil : .spring(response: 0.35, dampingFraction: 0.65),
                            value: progress
                        )
                }
            }
            .frame(height: 6)

            Text("\(current) / \(maximum)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isFull ? .green : .primary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize()
        }
        .modifier(CapacityPulseModifier(current: current, maximum: maximum, pulseOpacity: $pulseOpacity))
    }
}

#Preview("States") {
    VStack(spacing: 20) {
        CapacityProgressBar(current: 0, maximum: 120)
        CapacityProgressBar(current: 42, maximum: 120)
        CapacityProgressBar(current: 100, maximum: 120)
        CapacityProgressBar(current: 120, maximum: 120)
    }
    .padding()
}

#Preview("Celebration") {
    struct CelebrationDemo: View {
        @State private var count = 119

        var body: some View {
            VStack(spacing: 20) {
                CapacityProgressBar(current: count, maximum: 120)

                Button("Fill Library") {
                    count = 120
                }
                .buttonStyle(.borderedProminent)

                Button("Reset") {
                    count = 119
                }
            }
            .padding()
        }
    }
    return CelebrationDemo()
}

struct CapacityRing: View {
    let current: Int
    let maximum: Int

    @State private var pulseOpacity: Double = 0

    private var progress: Double {
        CapacityProgressBar.calculateProgress(current: current, maximum: maximum)
    }

    private var isFull: Bool {
        current >= maximum
    }

    private var ringColor: Color {
        isFull ? .green : .accentColor
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .brightness(pulseOpacity * 0.3)
                    .animation(
                        progress == 0 ? nil : .spring(response: 0.35, dampingFraction: 0.65),
                        value: progress
                    )
            }
            .frame(width: 22, height: 22)

            HStack(spacing: 2) {
                Text("\(current)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isFull ? .green : .primary)
                    .contentTransition(.numericText())
                Text("of \(maximum)")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .modifier(CapacityPulseModifier(current: current, maximum: maximum, pulseOpacity: $pulseOpacity))
    }
}

#Preview("Ring States") {
    VStack(spacing: 20) {
        CapacityRing(current: 0, maximum: 120)
        CapacityRing(current: 5, maximum: 120)
        CapacityRing(current: 80, maximum: 120)
        CapacityRing(current: 120, maximum: 120)
    }
    .padding()
}

#Preview("Compact States") {
    VStack(spacing: 16) {
        CompactCapacityBar(current: 0, maximum: 120)
        CompactCapacityBar(current: 5, maximum: 120)
        CompactCapacityBar(current: 80, maximum: 120)
        CompactCapacityBar(current: 120, maximum: 120)
    }
    .padding()
}
