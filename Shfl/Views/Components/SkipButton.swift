import SwiftUI

struct SkipButton: View {
    let action: () -> Void

    @State private var tapCount = 0

    var body: some View {
        Button(action: {
            tapCount += 1
            action()
        }) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

                Image(systemName: "forward.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.black.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}

#Preview {
    SkipButton {}
        .padding()
        .background(Color.gray.opacity(0.2))
}
