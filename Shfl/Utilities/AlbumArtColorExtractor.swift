import Combine
import MusicKit
import SwiftUI
import UIKit

/// Extracts colors from album artwork using MusicKit's catalog data
@MainActor
final class AlbumArtColorExtractor: ObservableObject {
    @Published private(set) var extractedColor: Color?

    private var currentSongId: String?
    private var currentTask: Task<Void, Never>?
    private var colorCache: [String: Color] = [:]

    /// Updates the extracted color for the given song by fetching from Apple Music catalog
    func updateColor(for songId: String) {
        // Skip if already processing this song
        guard songId != currentSongId else { return }
        currentSongId = songId

        // Check cache first
        if let cached = colorCache[songId] {
            print("[ColorExtractor] Using cached color for songId: \(songId)")
            withAnimation(.easeInOut(duration: 0.5)) {
                extractedColor = cached
            }
            return
        }

        // Cancel any existing task
        currentTask?.cancel()

        print("[ColorExtractor] Fetching catalog data for songId: \(songId)")
        currentTask = Task {
            do {
                // Fetch from catalog to get full artwork metadata
                let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: MusicItemID(songId))
                let response = try await request.response()

                guard !Task.isCancelled, currentSongId == songId else { return }

                guard let song = response.items.first else {
                    print("[ColorExtractor] No song found in catalog for songId: \(songId)")
                    return
                }

                print("[ColorExtractor] Artwork object: \(String(describing: song.artwork))")

                guard let artwork = song.artwork,
                      let bgColor = artwork.backgroundColor else {
                    print("[ColorExtractor] No backgroundColor available from catalog for songId: \(songId)")
                    return
                }

                // let color = boostColorIfNeeded(Color(cgColor: bgColor))
                let color = Color(cgColor: bgColor) // raw, no boost
                colorCache[songId] = color

                let uiColor = UIColor(color)
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
                uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
                print("[ColorExtractor] Got catalog backgroundColor - hue: \(h), sat: \(s), bright: \(b)")

                withAnimation(.easeInOut(duration: 0.5)) {
                    extractedColor = color
                }
            } catch {
                print("[ColorExtractor] Failed to fetch catalog data: \(error)")
            }
        }
    }

    /// Clears the extracted color (used when playback stops)
    func clear() {
        currentTask?.cancel()
        currentSongId = nil
        withAnimation(.easeInOut(duration: 0.5)) {
            extractedColor = nil
        }
    }

    // MARK: - Color adjustment

    private func boostColorIfNeeded(_ color: Color) -> Color {
        let uiColor = UIColor(color)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Boost saturation for visibility
        let boostedSaturation = max(saturation, 0.5)

        // Ensure good brightness range
        let boostedBrightness = min(max(brightness, 0.6), 0.95)

        return Color(hue: hue, saturation: boostedSaturation, brightness: boostedBrightness)
    }
}
