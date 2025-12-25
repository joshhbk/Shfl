import SwiftUI

struct CapacityIndicator: View {
    let current: Int
    let maximum: Int

    var body: some View {
        Text("\(current)/\(maximum)")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
    }
}

#Preview {
    VStack(spacing: 20) {
        CapacityIndicator(current: 0, maximum: 120)
        CapacityIndicator(current: 47, maximum: 120)
        CapacityIndicator(current: 120, maximum: 120)
    }
    .padding()
}
