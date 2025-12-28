import MusicKit
import SwiftUI
import UIKit

/// Extracts colors from album artwork using MusicKit's built-in Artwork.backgroundColor
@MainActor
final class AlbumArtColorExtractor: ObservableObject {
    @Published private(set) var extractedColor: Color?

    private var currentSongId: String?

    /// Updates the extracted color from the artwork for the given song
    /// - Parameter songId: The song ID to extract color for
    func updateColor(for songId: String) {
        currentSongId = songId

        // Request artwork load if not cached
        ArtworkLoader.shared.requestArtwork(for: songId)

        // Try to get color from cached artwork
        refreshFromLoader()
    }

    /// Called when artwork loader updates - checks if our song's artwork is now available
    func refreshFromLoader() {
        guard let songId = currentSongId,
              let artwork = ArtworkLoader.shared.artwork(for: songId),
              let bgColor = artwork.backgroundColor else {
            return
        }

        let color = Color(cgColor: bgColor)
        let boostedColor = boostColorIfNeeded(color)

        // Only animate if color actually changed
        if extractedColor != boostedColor {
            withAnimation(.easeInOut(duration: 0.5)) {
                extractedColor = boostedColor
            }
        }
    }

    /// Clears the extracted color (used when playback stops)
    func clear() {
        currentSongId = nil
        withAnimation(.easeInOut(duration: 0.5)) {
            extractedColor = nil
        }
    }

    // MARK: - Private

    /// Boosts saturation and brightness if the color is too dark or desaturated
    private func boostColorIfNeeded(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Boost saturation if too low (for better visibility on glint)
        let minSaturation: CGFloat = 0.4
        let boostedSaturation = max(saturation, minSaturation)

        // Boost brightness if too dark, cap if too bright
        let minBrightness: CGFloat = 0.5
        let maxBrightness: CGFloat = 0.9
        let boostedBrightness = min(max(brightness, minBrightness), maxBrightness)

        return Color(hue: hue, saturation: boostedSaturation, brightness: boostedBrightness)
    }
}
