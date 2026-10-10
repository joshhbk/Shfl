import SwiftUI

struct DraftFailureMessage: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        if let message = drafting.failureMessage {
            HStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("mac.draft.failure")
                Spacer()
                Button("Dismiss", systemImage: "xmark", action: drafting.dismissFailure)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.red.opacity(0.08))
        }
    }
}
