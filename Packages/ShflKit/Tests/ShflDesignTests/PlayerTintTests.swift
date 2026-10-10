import SwiftUI
import Testing
@testable import ShflDesign

@Suite("Player tint")
@MainActor
struct PlayerTintTests {
    let tone = Color.Resolved(hex: 0x1E2A5A)

    @Test("Without artwork the body is the theme colour")
    func untinted() {
        let body = DesignColor.playerBody.resolve(in: environment(theme: .blue, scheme: .light))
        #expect(hex(body) == 0x2B5FC0)
    }

    @Test("Artwork mixes a quarter of its tone into the body")
    func tinted() {
        let body = DesignColor.playerBody.resolve(in: environment(theme: .blue, scheme: .light, tone: tone))
        let expected = ColorMath.mix(.init(hex: 0x2B5FC0), with: tone, share: 0.24)
        #expect(hex(body) == hex(expected))
        #expect(hex(body) != 0x2B5FC0)
    }

    @Test("Silver keeps more of its own colour so dark ink stays readable")
    func silverTintsLess() {
        let body = DesignColor.playerBody.resolve(in: environment(theme: .silver, scheme: .light, tone: tone))
        #expect(hex(body) == hex(ColorMath.mix(.init(hex: 0xA9A8AD), with: tone, share: 0.10)))
    }

    @Test("Increase Contrast drops the tint, solidifies hairlines and secondary ink")
    func increasedContrast() {
        let environment = environment(theme: .blue, scheme: .light, tone: tone, contrast: .increased)
        #expect(hex(DesignColor.playerBody.resolve(in: environment)) == 0x2B5FC0)
        #expect(DesignColor.hairline.resolve(in: environment).opacity == 1)
        #expect(DesignColor.inkSecondary.resolve(in: environment).opacity == 1)
    }

    @Test("Secondary ink stays at 84% where that's readable, and firms up where it isn't")
    func secondaryInk() {
        let dark = DesignColor.inkSecondary.resolve(in: environment(theme: .pink, scheme: .dark))
        let light = DesignColor.inkSecondary.resolve(in: environment(theme: .pink, scheme: .light))
        #expect(abs(dark.opacity - 0.84) < 0.001)
        #expect(light.opacity > 0.84)
    }

    @Test("Mixing in OKLab: no share keeps the base, half of black and white is OKLab mid-grey")
    func oklab() {
        let white = Color.Resolved(hex: 0xFFFFFF)
        let black = Color.Resolved(hex: 0x000000)
        #expect(hex(ColorMath.mix(white, with: black, share: 0)) == 0xFFFFFF)
        #expect(hex(ColorMath.mix(white, with: black, share: 1)) == 0x000000)
        #expect(hex(ColorMath.mix(white, with: black, share: 0.5)) == 0x636363)
    }

    private func hex(_ color: Color.Resolved) -> UInt32 {
        func byte(_ component: Float) -> UInt32 { UInt32((min(max(component, 0), 1) * 255).rounded()) }
        return byte(color.red) << 16 | byte(color.green) << 8 | byte(color.blue)
    }
}
