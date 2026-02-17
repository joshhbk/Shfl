import MusicKit
import SwiftUI

/// Extracts colors from album artwork using MusicKit's library data
@Observable
@MainActor
final class AlbumArtColorExtractor {
    private(set) var extractedColor: Color?

    @ObservationIgnored private var currentSongId: String?
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var candidateCache: [String: [Color]] = [:]

    static let minimumVibrancyThreshold: Double = 0.1

    /// Updates the extracted color for the given song by fetching from user's library
    func updateColor(for songId: String) {
        // Skip if already processing this song
        guard songId != currentSongId else { return }
        currentSongId = songId

        // Check cache first — randomly select from cached candidates
        if let cached = candidateCache[songId] {
            let selected = cached.randomElement()
            #if DEBUG
            if let selected {
                let hsb = ColorBlending.extractHSB(from: selected)
                print("[ColorExtractor] Randomly selected from \(cached.count) cached candidate(s) for songId: \(songId) — hue: \(String(format: "%.2f", hsb.hue)) sat: \(String(format: "%.2f", hsb.saturation)) bright: \(String(format: "%.2f", hsb.brightness))")
            } else {
                print("[ColorExtractor] No viable cached candidates for songId: \(songId), using theme default")
            }
            #endif
            extractedColor = selected
            return
        }

        // Cancel any existing task
        currentTask?.cancel()

        #if DEBUG
        print("[ColorExtractor] Fetching library data for songId: \(songId)")
        #endif
        currentTask = Task {
            do {
                // Fetch from library using library ID
                var request = MusicLibraryRequest<MusicKit.Song>()
                request.filter(matching: \.id, equalTo: MusicItemID(songId))
                let response = try await request.response()

                guard !Task.isCancelled, currentSongId == songId else { return }

                guard let song = response.items.first else {
                    #if DEBUG
                    print("[ColorExtractor] No song found in library for songId: \(songId)")
                    #endif
                    candidateCache[songId] = []
                    extractedColor = nil
                    return
                }

                #if DEBUG
                print("[ColorExtractor] Artwork object: \(String(describing: song.artwork))")
                #endif

                guard let artwork = song.artwork else {
                    #if DEBUG
                    print("[ColorExtractor] No artwork available for songId: \(songId)")
                    #endif
                    candidateCache[songId] = []
                    extractedColor = nil
                    return
                }

                let candidates = Self.vibrantCandidates(from: artwork)
                candidateCache[songId] = candidates

                let selected = candidates.randomElement()

                #if DEBUG
                if let selected {
                    let hsb = ColorBlending.extractHSB(from: selected)
                    print("[ColorExtractor] Randomly selected from \(candidates.count) candidate(s) for songId: \(songId) — hue: \(String(format: "%.2f", hsb.hue)) sat: \(String(format: "%.2f", hsb.saturation)) bright: \(String(format: "%.2f", hsb.brightness))")
                } else {
                    print("[ColorExtractor] No candidates passed vibrancy threshold for songId: \(songId), using theme default")
                }
                #endif

                extractedColor = selected
            } catch {
                #if DEBUG
                print("[ColorExtractor] Failed to fetch library data: \(error)")
                #endif
                extractedColor = nil
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

    /// Filters labeled color candidates by vibrancy threshold.
    /// Score = saturation × brightness. This naturally penalizes dark colors
    /// (which can have high HSB saturation but look black) and desaturated
    /// colors (grays/whites) equally.
    nonisolated static func filterByVibrancy(_ candidates: [(color: Color, label: String)]) -> [Color] {
        guard !candidates.isEmpty else { return [] }

        let scored = candidates.map { candidate in
            let hsb = ColorBlending.extractHSB(from: candidate.color)
            let score = hsb.saturation * hsb.brightness
            #if DEBUG
            print("[ColorExtractor]   \(candidate.label): hue=\(String(format: "%.2f", hsb.hue)) sat=\(String(format: "%.2f", hsb.saturation)) bright=\(String(format: "%.2f", hsb.brightness)) score=\(String(format: "%.3f", score))")
            #endif
            return (candidate.color, score)
        }

        let passing = scored
            .filter { $0.1 >= minimumVibrancyThreshold }
            .map { $0.0 }

        // Vibrant colors preferred, but any album color is acceptable
        return passing.isEmpty ? scored.map { $0.0 } : passing
    }

    /// Evaluates all available artwork colors and returns those above the vibrancy threshold.
    /// MusicKit provides backgroundColor, primaryTextColor, secondaryTextColor,
    /// tertiaryTextColor, and quaternaryTextColor — we score each by vibrancy.
    private static func vibrantCandidates(from artwork: MusicKit.Artwork) -> [Color] {
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

        return filterByVibrancy(candidates)
    }
}
