import SwiftUI

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

            Text(isFull ? "Ready!" : "\(current) / \(maximum)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isFull ? .green : .secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
        .onChange(of: current) { oldValue, newValue in
            if Self.shouldCelebrate(previous: oldValue, current: newValue, maximum: maximum) {
                HapticFeedback.success.trigger()
            }

            // Pulse on add (not on clear)
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
                        .fill(Color.white.opacity(0.08))

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

            Text(isFull ? "Ready!" : "\(current) / \(maximum)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isFull ? .green : .secondary)
                .monospacedDigit()
                .fixedSize()
        }
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
