import Foundation
import Testing
@testable import Shfl

@Suite("ShuffleTheme Tests")
struct ShuffleThemeTests {

    @Test("All themes have unique IDs")
    func allThemesHaveUniqueIds() {
        let ids = ShuffleTheme.allThemes.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "All theme IDs should be unique")
    }

    @Test("Should have 5 themes")
    func allThemesCount() {
        #expect(ShuffleTheme.allThemes.count == 5, "Should have 5 themes")
    }

    @Test("Silver has dark wheel style")
    func silverHasDarkWheelStyle() {
        #expect(ShuffleTheme.silver.wheelStyle == .dark)
    }

    @Test("Silver has dark text style")
    func silverHasDarkTextStyle() {
        #expect(ShuffleTheme.silver.textStyle == .dark)
    }

    @Test("Colorful themes have light wheel style")
    func colorfulThemesHaveLightWheelStyle() {
        let colorfulThemes = [ShuffleTheme.blue, .green, .orange, .pink]
        for theme in colorfulThemes {
            #expect(theme.wheelStyle == .light, "\(theme.name) should have light wheel")
        }
    }

    @Test("Colorful themes have light text style")
    func colorfulThemesHaveLightTextStyle() {
        let colorfulThemes = [ShuffleTheme.blue, .green, .orange, .pink]
        for theme in colorfulThemes {
            #expect(theme.textStyle == .light, "\(theme.name) should have light text")
        }
    }

    @Test("Random theme returns a valid theme")
    func randomThemeReturnsValidTheme() {
        for _ in 0..<20 {
            let theme = ShuffleTheme.random()
            let isValid = ShuffleTheme.allThemes.contains { $0.id == theme.id }
            #expect(isValid, "Random theme should be one of the predefined themes")
        }
    }

    @Test("All themes have brushed metal configuration")
    func allThemesHaveBrushedMetalConfig() {
        for theme in ShuffleTheme.allThemes {
            #expect(theme.brushedMetalIntensity >= 0 && theme.brushedMetalIntensity <= 1)
        }
    }

    @Test("Each theme has an accent color matching bodyGradientTop")
    func accentColorMatchesBodyGradientTop() {
        for theme in ShuffleTheme.allThemes {
            #expect(theme.accentColor == theme.bodyGradientTop)
        }
    }
}
