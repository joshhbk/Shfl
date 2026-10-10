import ShflCore
import SwiftUI

/// Picks a tint colour for the playing song from its album artwork's palette,
/// rotating through the palette so songs from one album don't repeat a colour.
@Observable
@MainActor
final class AlbumArtColorExtractor {
    deinit {} // Keep nonisolated: Xcode 27 synthesizes an isolated one that can crash on release. See ViewTeardownTests.
    private(set) var extractedColor: Color?

    @ObservationIgnored private var currentSongId: String?
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    @ObservationIgnored private var candidateCache: [String: [Color]] = [:]

    /// Tracks the last-used color index per unique palette, so songs from the same album
    /// cycle through colors rather than randomly repeating.
    @ObservationIgnored private var lastUsedIndex: [Int: Int] = [:]

    /// A nil palette (no artwork store this launch) leaves the theme default.
    func updateColor(for songId: String, palette: ArtworkPalette?) {
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

        guard let palette else {
            extractedColor = nil
            return
        }

        #if DEBUG
        print("[ColorExtractor] Fetching artwork palette for songId: \(songId)")
        #endif
        currentTask = Task {
            let candidates = await palette.colors(for: .song(id: songId))

            guard !Task.isCancelled, currentSongId == songId else { return }

            guard let candidates else {
                #if DEBUG
                print("[ColorExtractor] No artwork available for songId: \(songId)")
                #endif
                candidateCache[songId] = []
                extractedColor = nil
                return
            }

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
}
