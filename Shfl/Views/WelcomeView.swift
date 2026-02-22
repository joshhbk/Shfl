import SwiftUI

struct WelcomeView: View {
    let onConnect: () -> Void

    @State private var themeIndex = Int.random(in: 0..<ShuffleTheme.allThemes.count)

    private var theme: ShuffleTheme {
        ShuffleTheme.allThemes[themeIndex]
    }

    var body: some View {
        ZStack {
            BrushedMetalBackground()

            VStack(spacing: 0) {
                Spacer()

                WelcomeClickWheel()
                    .padding(.bottom, 40)

                WelcomeHeader()

                Spacer()

                WelcomeConnectButton(onConnect: onConnect)
                    .padding(.bottom, 16)

                WelcomeThemeDots(activeIndex: themeIndex)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .environment(\.shuffleTheme, theme)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                let nextIndex = (themeIndex + 1) % ShuffleTheme.allThemes.count
                withAnimation(.easeInOut(duration: 0.8)) {
                    themeIndex = nextIndex
                }
            }
        }
    }
}

// MARK: - Click Wheel (decorative)

private struct WelcomeClickWheel: View {
    var body: some View {
        ClickWheelView(
            isPlaying: false,
            onPlayPause: {},
            onSkipForward: {},
            onSkipBack: {},
            onVolumeUp: {},
            onVolumeDown: {},
            scale: 0.85
        )
        .allowsHitTesting(false)
        .opacity(0.75)
    }
}

// MARK: - Header

private struct WelcomeHeader: View {
    @Environment(\.shuffleTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Text("Shuffled")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textColor)

            Text("Your music, reshuffled")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.secondaryTextColor)
        }
    }
}

// MARK: - Connect Button

private struct WelcomeConnectButton: View {
    @Environment(\.shuffleTheme) private var theme
    let onConnect: () -> Void

    private var backgroundColor: Color {
        switch theme.textStyle {
        case .light:
            return .white
        case .dark:
            return Color(white: 0.15)
        }
    }

    private var textColor: Color {
        switch theme.textStyle {
        case .light:
            return .black
        case .dark:
            return .white
        }
    }

    var body: some View {
        Button(action: onConnect) {
            Text("Connect Apple Music")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(backgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Dots

private struct WelcomeThemeDots: View {
    let activeIndex: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(ShuffleTheme.allThemes.enumerated()), id: \.element.id) { index, theme in
                Circle()
                    .fill(theme.bodyGradientTop)
                    .frame(width: 8, height: 8)
                    .opacity(index == activeIndex ? 1.0 : 0.4)
            }
        }
    }
}

#Preview {
    WelcomeView(onConnect: {})
}
