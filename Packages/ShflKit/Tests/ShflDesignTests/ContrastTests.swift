import SwiftUI
import Testing
@testable import ShflDesign

@Suite("Contrast")
@MainActor
struct ContrastTests {
    static let schemes: [ColorScheme] = [.light, .dark]
    static let surfaces: [DesignColor] = [.surfaceWindow, .surfaceContent, .surfaceElevated, .surfaceSidebar, .surfacePane]
    /// The canvas's sample artwork tones, plus black as the darkest a tone can be.
    static let tones: [Color.Resolved?] = [nil, .init(hex: 0x1E2A5A), .init(hex: 0x43205E), .init(hex: 0x7A1E18), .init(hex: 0x000000)]

    @Test("Player text holds 4.5:1 on the player body in every theme, scheme and tint", arguments: ShflTheme.all, schemes)
    func playerText(theme: ShflTheme, scheme: ColorScheme) {
        for tone in Self.tones {
            let environment = environment(theme: theme, scheme: scheme, tone: tone)
            let body = DesignColor.playerBody.resolve(in: environment)
            for text in [DesignColor.ink, .inkSecondary] {
                let ratio = ColorMath.contrastRatio(text.resolve(in: environment), on: body)
                #expect(ratio >= ColorMath.minimumTextContrast, "\(text.role) on \(theme.id) \(scheme) tone \(String(describing: tone)): \(ratio)")
            }
        }
    }

    @Test("Accent text holds 4.5:1 on every surface", arguments: ShflTheme.all, schemes)
    func accentText(theme: ShflTheme, scheme: ColorScheme) {
        let environment = environment(theme: theme, scheme: scheme)
        for surface in Self.surfaces {
            expectReadable(.accentText, on: surface, in: environment)
        }
    }

    @Test("Text on accent fills holds 4.5:1", arguments: ShflTheme.all, schemes)
    func onAccent(theme: ShflTheme, scheme: ColorScheme) {
        expectReadable(.onAccent, on: .accentFill, in: environment(theme: theme, scheme: scheme))
    }

    @Test("Neutral text holds 4.5:1 on every surface", arguments: schemes)
    func neutralText(scheme: ColorScheme) {
        let environment = environment(theme: .pink, scheme: scheme)
        for surface in Self.surfaces {
            for text in [DesignColor.textPrimary, .textSecondary, .textTertiary, .warning, .successText] {
                expectReadable(text, on: surface, in: environment)
            }
        }
    }

    @Test("Wheel and chrome glyphs hold 4.5:1", arguments: schemes)
    func darkChrome(scheme: ColorScheme) {
        let environment = environment(theme: .pink, scheme: scheme)
        expectReadable(.wheelGlyph, on: .wheel, in: environment)
        expectReadable(.chromeGlyph, on: .chrome, in: environment)
        expectReadable(.chromeText, on: .chrome, in: environment)
        expectReadable(.chromeTextSecondary, on: .chrome, in: environment)
    }

    private func expectReadable(
        _ text: DesignColor,
        on surface: DesignColor,
        in environment: EnvironmentValues,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let ratio = ColorMath.contrastRatio(text.resolve(in: environment), on: surface.resolve(in: environment))
        #expect(
            ratio >= ColorMath.minimumTextContrast,
            "\(text.role) on \(surface.role), \(environment.shflTheme.id) \(environment.colorScheme): \(ratio)",
            sourceLocation: sourceLocation
        )
    }
}

@MainActor
func environment(
    theme: ShflTheme,
    scheme: ColorScheme,
    tone: Color.Resolved? = nil,
    contrast: ColorSchemeContrast = .standard
) -> EnvironmentValues {
    var environment = EnvironmentValues()
    environment.shflTheme = theme
    environment.colorScheme = scheme
    environment.artworkTone = tone
    environment._colorSchemeContrast = contrast
    return environment
}
