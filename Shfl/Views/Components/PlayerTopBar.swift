import SwiftUI

/// Top bar with Add and Settings buttons for the player view
struct PlayerTopBar: View {
    @Environment(\.shuffleTheme) private var theme
    @Environment(\.appSettings) private var appSettings

    let onAddTapped: () -> Void
    let onSettingsTapped: () -> Void
    let topPadding: CGFloat

    /// Device theme accent color — always visible against the dark button background.
    private var iconColor: Color {
        guard let themeId = appSettings?.currentThemeId,
              let deviceTheme = ShuffleTheme.theme(byId: themeId) else {
            return .white
        }
        return deviceTheme.accentColor
    }

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
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
        }
        .modifier(CircularButtonStyle())
    }

    private var settingsButton: some View {
        Button(action: onSettingsTapped) {
            Image(systemName: "gearshape")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
        }
        .modifier(CircularButtonStyle())
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

/// Applies a consistent dark circular background so the device accent icon is always readable
private struct CircularButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .background(.black.opacity(0.8), in: Circle())
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(.black.opacity(0.8), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                )
        }
    }
}
