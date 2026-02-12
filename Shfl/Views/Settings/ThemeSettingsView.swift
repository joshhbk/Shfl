import SwiftUI

struct ThemeSettingsView: View {
    @Environment(\.appSettings) private var appSettings

    private var selectedTheme: ShuffleTheme {
        guard let id = appSettings?.currentThemeId else { return .pink }
        return ShuffleTheme.theme(byId: id) ?? .pink
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                ThemePreviewBody(theme: selectedTheme)
                    .padding(.top, 24)

                VStack(spacing: 16) {
                    colorDotPicker

                    Text(selectedTheme.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Theme")
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: selectedTheme)
    }

    private var colorDotPicker: some View {
        HStack(spacing: 16) {
            ForEach(ShuffleTheme.allThemes) { theme in
                ThemeColorDot(
                    theme: theme,
                    isSelected: selectedTheme.id == theme.id,
                    action: {
                        guard selectedTheme.id != theme.id else { return }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            appSettings?.currentThemeId = theme.id
                        }
                        HapticFeedback.light.trigger()
                    }
                )
            }
        }
    }
}

// MARK: - Theme Preview Body

private struct ThemePreviewBody: View {
    let theme: ShuffleTheme

    private let cornerRadius: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(theme.bodyGradient)
            .frame(height: 180)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.35), .clear, .black.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }
}

// MARK: - Theme Color Dot

private struct ThemeColorDot: View {
    let theme: ShuffleTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(theme.bodyGradient)
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
                .padding(4)
                .overlay {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: isSelected ? 2 : 0)
                        .frame(width: 44, height: 44)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        ThemeSettingsView()
    }
    .environment(\.appSettings, AppSettings())
}
