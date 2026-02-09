import MusicKit
import SwiftUI

/// Extracts colors from album artwork using MusicKit's library data
@Observable
@MainActor
final class AlbumArtColorExtractor {
    private(set) var extractedColor: Color?

    @ObservationIgnored private var currentSongId: String?
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var colorCache: [String: Color] = [:]

    /// Updates the extracted color for the given song by fetching from user's library
    func updateColor(for songId: String) {
        // Skip if already processing this song
        guard songId != currentSongId else { return }
        currentSongId = songId

        // Check cache first
        if let cached = colorCache[songId] {
            print("[ColorExtractor] Using cached color for songId: \(songId)")
            // No animation here - TintedThemeProvider handles the visual transition
            extractedColor = cached
            return
        }

        // Cancel any existing task
        currentTask?.cancel()

        print("[ColorExtractor] Fetching library data for songId: \(songId)")
        currentTask = Task {
            do {
                // Fetch from library using library ID
                var request = MusicLibraryRequest<MusicKit.Song>()
                request.filter(matching: \.id, equalTo: MusicItemID(songId))
                let response = try await request.response()

                guard !Task.isCancelled, currentSongId == songId else { return }

                guard let song = response.items.first else {
                    print("[ColorExtractor] No song found in library for songId: \(songId)")
                    return
                }

                print("[ColorExtractor] Artwork object: \(String(describing: song.artwork))")

                guard let artwork = song.artwork else {
                    print("[ColorExtractor] No artwork available for songId: \(songId)")
                    return
                }

                let color = Self.pickMostVibrant(from: artwork)

                guard let color else {
                    print("[ColorExtractor] No usable colors from artwork for songId: \(songId)")
                    return
                }

                colorCache[songId] = color

                let hsb = ColorBlending.extractHSB(from: color)
                print("[ColorExtractor] Selected color - hue: \(hsb.hue), sat: \(hsb.saturation), bright: \(hsb.brightness)")

                // No animation here - TintedThemeProvider handles the visual transition
                extractedColor = color
            } catch {
                print("[ColorExtractor] Failed to fetch library data: \(error)")
            }
        }
    }

    /// Clears the extracted color (used when playback stops)
    func clear() {
        currentTask?.cancel()
        currentSongId = nil
        // No animation here - TintedThemeProvider handles the visual transition
        extractedColor = nil
    }

    // MARK: - Color selection

    /// Evaluates all available artwork colors and picks the most vibrant one.
    /// MusicKit provides backgroundColor, primaryTextColor, secondaryTextColor,
    /// tertiaryTextColor, and quaternaryTextColor — we score each by vibrancy.
    private static func pickMostVibrant(from artwork: MusicKit.Artwork) -> Color? {
        var candidates: [(color: Color, label: String)] = []

        if let c = artwork.backgroundColor {
            candidates.append((Color(cgColor: c), "background"))
        }
        if let c = artwork.primaryTextColor {
            candidates.append((Color(cgColor: c), "primaryText"))
        }
        if let c = artwork.secondaryTextColor {
            candidates.append((Color(cgColor: c), "secondaryText"))
        }
        if let c = artwork.tertiaryTextColor {
            candidates.append((Color(cgColor: c), "tertiaryText"))
        }
        if let c = artwork.quaternaryTextColor {
            candidates.append((Color(cgColor: c), "quaternaryText"))
        }

        guard !candidates.isEmpty else { return nil }

        let scored = candidates.map { candidate in
            let hsb = ColorBlending.extractHSB(from: candidate.color)
            // Score = saturation * brightness. This naturally penalizes
            // dark colors (which can have high HSB saturation but look black)
            // and desaturated colors (grays/whites) equally.
            let score = hsb.saturation * hsb.brightness
            print("[ColorExtractor]   \(candidate.label): hue=\(String(format: "%.2f", hsb.hue)) sat=\(String(format: "%.2f", hsb.saturation)) bright=\(String(format: "%.2f", hsb.brightness)) score=\(String(format: "%.3f", score))")
            return (candidate.color, score)
        }

        return scored.max(by: { $0.1 < $1.1 })?.0
    }
}
