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
            Spacer()
            buttonGroup
        }
        .modifier(GlassContainerModifier())
        .padding(.horizontal, 20)
        .padding(.top, topPadding)
        .padding(.bottom, 16)
    }

    private var buttonGroup: some View {
        HStack(spacing: 4) {
            Button(action: onAddTapped) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 48, height: 48)
            }
            Button(action: onSettingsTapped) {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 48, height: 48)
            }
        }
        .padding(.horizontal, 4)
        .modifier(CapsuleButtonGroupStyle())
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

// MARK: - Capsule Button Group Style

/// Wraps grouped buttons in a single capsule container
private struct CapsuleButtonGroupStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, macOS 26, *) {
            content
                .background(.black.opacity(0.85), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.black.opacity(0.85), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        }
    }
}
