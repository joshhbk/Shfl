import SwiftUI

struct ClickWheelButton: View {
    let systemName: String
    let action: () -> Void

    @State private var tapCount = 0

    var body: some View {
        Button(action: {
            tapCount += 1
            action()
        }) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(white: 0.3))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
    }
}

#Preview {
    HStack(spacing: 20) {
        ClickWheelButton(systemName: "plus") {}
        ClickWheelButton(systemName: "minus") {}
        ClickWheelButton(systemName: "backward.end.fill") {}
        ClickWheelButton(systemName: "forward.end.fill") {}
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
