import SwiftUI

/// Top bar with Add and Settings buttons for the player view
struct PlayerTopBar: View {
    @Environment(\.shuffleTheme) private var theme

    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void
    let topPadding: CGFloat

    var body: some View {
        HStack {
            addButton
            Spacer()
            settingsButton
        }
        .modifier(GlassContainerModifier())
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
        .padding(.bottom, 16)
    }

    private var addButton: some View {
        Button(action: onAddTapped) {
            Image(systemName: "music.note.list")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .modifier(CircularButtonStyle(fallbackColor: theme.bodyGradientTop))
    }

    private var settingsButton: some View {
        Button(action: onSettingsTapped) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .modifier(CircularButtonStyle(fallbackColor: theme.bodyGradientTop))
    }
}

// MARK: - Glass Container Modifier

/// Wraps content in GlassEffectContainer on iOS 26+, applies shadow on older versions
private struct GlassContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            GlassEffectContainer {
                content
            }
        } else {
            content
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
    }
}

// MARK: - Circular Button Style

/// Applies liquid glass effect on iOS 26+, solid color background on older versions
private struct CircularButtonStyle: ViewModifier {
    let fallbackColor: Color

    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(fallbackColor)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                )
        }
    }
}
