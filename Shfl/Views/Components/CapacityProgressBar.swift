import SwiftUI

struct CapacityProgressBar: View {
    let current: Int
    let maximum: Int


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
                        .animation(progress == 0 ? nil : .spring(response: 0.4, dampingFraction: 0.7), value: progress)
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
