import ShflCore
import SwiftUI

struct SelectedMeter: View {
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let count = drafting.draft.songCount
        let capacity = drafting.draft.capacity
        VStack(alignment: .trailing, spacing: 3) {
            Text("Selected \(count) / \(capacity)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressView(value: Double(count), total: Double(capacity))
                .progressViewStyle(.linear)
                .frame(width: 96)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: drafting.milestonePulses) { content, scale in
            content.scaleEffect(scale, anchor: .trailing)
        } keyframes: { _ in
            SpringKeyframe(1.12, duration: 0.15)
            SpringKeyframe(1.0, duration: 0.35)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Selected")
        .accessibilityValue("\(count) of \(capacity) songs")
        .accessibilityIdentifier("mac.meter.selected")
    }
}
