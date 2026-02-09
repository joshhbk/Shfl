import Foundation
import SwiftUI
import Testing
@testable import Shfl

@Suite("ColorBlending Tests")
struct ColorBlendingTests {

    @Test("extractHSB round-trips hue correctly")
    func extractHSBPreservesHue() {
        let color = Color(hue: 0.6, saturation: 0.8, brightness: 0.7)
        let hsb = ColorBlending.extractHSB(from: color)
        #expect(abs(hsb.hue - 0.6) < 0.01)
    }

    @Test("darken reduces brightness")
    func darkenReducesBrightness() {
        let color = Color(hue: 0.5, saturation: 0.7, brightness: 0.8)
        let darkened = ColorBlending.darken(color, by: 0.12)
        let hsb = ColorBlending.extractHSB(from: darkened)
        #expect(hsb.brightness < 0.8)
    }

    @Test("darken preserves hue and saturation")
    func darkenPreservesHueAndSaturation() {
        let color = Color(hue: 0.3, saturation: 0.6, brightness: 0.7)
        let darkened = ColorBlending.darken(color, by: 0.12)
        let original = ColorBlending.extractHSB(from: color)
        let result = ColorBlending.extractHSB(from: darkened)
        #expect(abs(result.hue - original.hue) < 0.01)
        #expect(abs(result.saturation - original.saturation) < 0.01)
    }

    @Test("darken floors at minimum brightness")
    func darkenFloorsAtMinimum() {
        let dark = Color(hue: 0.5, saturation: 0.5, brightness: 0.1)
        let darkened = ColorBlending.darken(dark, by: 0.5)
        let hsb = ColorBlending.extractHSB(from: darkened)
        #expect(hsb.brightness >= 0.2 - 0.02)
    }

    @Test("determineStyles returns dark for bright colors")
    func determineStylesDarkForBright() {
        let bright = Color(hue: 0.15, saturation: 0.3, brightness: 0.95)
        let (wheel, text, _) = ColorBlending.determineStyles(for: bright)
        #expect(wheel == .dark)
        #expect(text == .dark)
    }

    @Test("determineStyles returns light for dark colors")
    func determineStylesLightForDark() {
        let dark = Color(hue: 0.6, saturation: 0.8, brightness: 0.3)
        let (wheel, text, _) = ColorBlending.determineStyles(for: dark)
        #expect(wheel == .light)
        #expect(text == .light)
    }
}
