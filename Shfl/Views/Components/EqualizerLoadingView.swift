import SwiftUI
import Vortex

struct LoadingView: View {
    let message: String

    @Environment(\.shuffleTheme) private var theme

    var body: some View {
        ZStack {
            BrushedMetalBackground()

            ShuffleParticles(currentTheme: theme)

            VStack(spacing: 32) {
                PulsingMusicNote()

                LoadingMessageText(message: message)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}

// MARK: - Shuffle Particles

struct ShuffleParticles: View {
    let currentTheme: ShuffleTheme
    private let particleThemes: [ShuffleTheme]
    private let system: VortexSystem

    init(currentTheme: ShuffleTheme) {
        self.currentTheme = currentTheme
        let particleThemes = ShuffleTheme.allThemes.filter { $0.id != currentTheme.id }
        self.particleThemes = particleThemes
        self.system = Self.makeSystem(tags: particleThemes.map { "theme-\($0.id)" })
    }

    var body: some View {
        VortexView(system) {
            ForEach(particleThemes) { theme in
                Circle()
                    .fill(theme.bodyGradientTop.opacity(0.5))
                    .frame(width: 45)
                    .tag("theme-\(theme.id)")
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private static func makeSystem(tags: [String]) -> VortexSystem {
        let system = VortexSystem(tags: tags)
        system.birthRate = 8
        system.lifespan = 4
        system.speed = 0.15
        system.speedVariation = 0.1
        system.angle = .zero
        system.angleRange = .degrees(360)
        system.size = 0.4
        system.sizeVariation = 0.3
        system.position = [0.5, 0.5]
        system.shape = .ellipse(radius: 0.3)
        return system
    }
}

// MARK: - Pulsing Music Note

private struct PulsingMusicNote: View {
    @Environment(\.shuffleTheme) private var theme
    @State private var pulsing = false

    var body: some View {
        Image(systemName: "music.note")
            .font(.system(size: 40, weight: .medium))
            .foregroundStyle(theme.textColor)
            .scaleEffect(pulsing ? 1.15 : 0.9)
            .opacity(pulsing ? 1 : 0.5)
            .animation(
                .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                value: pulsing
            )
            .onAppear { pulsing = true }
    }
}

// MARK: - Loading Message

private struct LoadingMessageText: View {
    let message: String

    @Environment(\.shuffleTheme) private var theme

    var body: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(theme.secondaryTextColor)
            .contentTransition(.opacity)
            .animation(.easeInOut, value: message)
    }
}

#Preview {
    LoadingView(message: "Finding songs in your library...")
        .environment(\.shuffleTheme, .pink)
}
