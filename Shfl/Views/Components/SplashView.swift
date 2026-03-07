import SwiftUI

struct SplashView: View {
    let theme: ShuffleTheme
    let onComplete: () -> Void

    @State private var showParticles = false
    @State private var morphBackground = false
    @State private var logoPulse = false
    @State private var logoFadeOut = false
    @State private var dismissing = false

    var body: some View {
        ZStack {
            SplashBackground(
                theme: theme,
                morphed: morphBackground
            )

            SplashParticles(
                theme: theme,
                visible: showParticles
            )

            SplashLogo(
                pulsing: logoPulse,
                fadedOut: logoFadeOut
            )
        }
        .opacity(dismissing ? 0 : 1)
        .scaleEffect(dismissing ? 1.08 : 1.0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .task {
            await startTimeline()
        }
    }

    @MainActor
    private func startTimeline() async {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        withAnimation(.easeIn(duration: 0.6)) {
            showParticles = true
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            logoPulse = true
        }

        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.8)) {
            morphBackground = true
        }

        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: 0.3)) {
            logoFadeOut = true
        }

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: 0.7)) {
            dismissing = true
        }

        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }

        onComplete()
    }
}

// MARK: - Splash Background

private struct SplashBackground: View {
    let theme: ShuffleTheme
    let morphed: Bool

    var body: some View {
        Rectangle()
            .fill(morphed ? theme.bodyGradientTop : Color("SplashBackground"))
            .ignoresSafeArea()
    }
}

// MARK: - Splash Particles

private struct SplashParticles: View {
    let theme: ShuffleTheme
    let visible: Bool

    var body: some View {
        ShuffleParticles(currentTheme: theme)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
    }
}

// MARK: - Splash Logo

private struct SplashLogo: View {
    let pulsing: Bool
    let fadedOut: Bool

    var body: some View {
        Image("SplashLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 27))
            .scaleEffect(fadedOut ? 0.8 : (pulsing ? 1.05 : 1.0))
            .opacity(fadedOut ? 0 : 1)
    }
}

#Preview {
    SplashView(theme: .pink, onComplete: {})
}
