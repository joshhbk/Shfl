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

    /// Tracks the last-used color index per unique palette, so songs from the same album
    /// cycle through colors rather than randomly repeating.
    @ObservationIgnored private var lastUsedIndex: [Int: Int] = [:]

    /// Updates the extracted color for the given song by fetching from user's library
    func updateColor(for songId: String) {
        // Skip if already processing this song
        guard songId != currentSongId else { return }
        currentSongId = songId

        // Check cache first
        if let cached = candidateCache[songId] {
            let selected = pickNext(from: cached)
            #if DEBUG
            if let selected {
                let hsb = ColorBlending.extractHSB(from: selected)
                print("[ColorExtractor] Randomly selected from \(cached.count) cached candidate(s) for songId: \(songId) — hue: \(String(format: "%.2f", hsb.hue)) sat: \(String(format: "%.2f", hsb.saturation)) bright: \(String(format: "%.2f", hsb.brightness))")
            } else {
                print("[ColorExtractor] No cached candidates for songId: \(songId), using theme default")
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

                let candidates = Self.artworkColors(from: artwork)
                candidateCache[songId] = candidates

                let selected = pickNext(from: candidates)

                #if DEBUG
                if let selected {
                    let hsb = ColorBlending.extractHSB(from: selected)
                    print("[ColorExtractor] Randomly selected from \(candidates.count) candidate(s) for songId: \(songId) — hue: \(String(format: "%.2f", hsb.hue)) sat: \(String(format: "%.2f", hsb.saturation)) bright: \(String(format: "%.2f", hsb.brightness))")
                } else {
                    print("[ColorExtractor] No candidates for songId: \(songId), using theme default")
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

    /// Picks the next color from a candidate list, cycling through all colors before repeating.
    /// Uses a stable hash of the palette so all songs sharing the same artwork rotate together.
    private func pickNext(from candidates: [Color]) -> Color? {
        guard !candidates.isEmpty else { return nil }
        guard candidates.count > 1 else { return candidates.first }

        let key = paletteKey(for: candidates)
        let last = lastUsedIndex[key] ?? -1
        // Pick a random index from everything except the last-used one
        var available = Array(candidates.indices)
        if last >= 0 && last < candidates.count {
            available.removeAll { $0 == last }
        }
        let nextIndex = available.randomElement()!
        lastUsedIndex[key] = nextIndex
        return candidates[nextIndex]
    }

    /// Generates a stable key for a color palette so same-album songs share rotation state.
    private func paletteKey(for colors: [Color]) -> Int {
        var hasher = Hasher()
        for color in colors {
            let hsb = ColorBlending.extractHSB(from: color)
            hasher.combine(Int(hsb.hue * 1000))
            hasher.combine(Int(hsb.saturation * 1000))
            hasher.combine(Int(hsb.brightness * 1000))
        }
        return hasher.finalize()
    }

    /// Collects all available artwork colors from MusicKit.
    /// MusicKit provides backgroundColor, primaryTextColor, secondaryTextColor,
    /// tertiaryTextColor, and quaternaryTextColor — any of them can be randomly selected.
    private static func artworkColors(from artwork: MusicKit.Artwork) -> [Color] {
        var colors: [Color] = []

        if let c = artwork.backgroundColor { colors.append(Color(cgColor: c)) }
        if let c = artwork.primaryTextColor { colors.append(Color(cgColor: c)) }
        if let c = artwork.secondaryTextColor { colors.append(Color(cgColor: c)) }
        if let c = artwork.tertiaryTextColor { colors.append(Color(cgColor: c)) }
        if let c = artwork.quaternaryTextColor { colors.append(Color(cgColor: c)) }

        return colors
    }
}
