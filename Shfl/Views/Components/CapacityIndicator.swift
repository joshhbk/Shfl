import SwiftUI

struct CapacityIndicator: View {
    let current: Int
    let maximum: Int

    var body: some View {
        Text("\(current)/\(maximum)")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.white.opacity(0.15))
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
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(red: 0.75, green: 0.22, blue: 0.32))
}
