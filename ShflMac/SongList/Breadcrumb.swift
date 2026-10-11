import ShflDesign
import SwiftUI

/// "‹ Artists › Beach House" in the toolbar. The chevron and the parent go back, as does ⌘[.
struct Breadcrumb: View {
    let parent: String
    let title: String

    @Environment(\.goBack) private var goBack

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Button("Back to \(parent)", systemImage: "chevron.left") { goBack?() }
                .labelStyle(.iconOnly)
                .keyboardShortcut("[", modifiers: .command)
            Button(parent) { goBack?() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Back to \(parent)")
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .font(.system(size: 15))
    }
}
