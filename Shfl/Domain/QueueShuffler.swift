import Foundation

struct QueueShuffler: Sendable {
    let algorithm: ShuffleAlgorithm

    func shuffle(_ songs: [Song], count: Int? = nil) -> [Song] {
        guard !songs.isEmpty else { return [] }

        switch algorithm {
        case .pureRandom:
            return pureRandom(songs, count: count ?? songs.count)
        case .noRepeat:
            return songs.shuffled()
        case .weightedByRecency:
            return weightedByRecency(songs)
        case .weightedByPlayCount:
            return weightedByPlayCount(songs)
        case .artistSpacing:
            return artistSpacing(songs)
        }
    }

    // MARK: - Pure Random

    private func pureRandom(_ songs: [Song], count: Int) -> [Song] {
        guard count > 0 else { return [] }

        // Queue-domain invariants require unique song IDs for normal queue builds.
        // For standard playback (`count == songs.count`), produce a full random permutation.
        if count <= songs.count {
            return Array(songs.shuffled().prefix(count))
        }

        // If a caller explicitly asks for more than available, allow repeats to fill overflow.
        var result = songs.shuffled()
        result.reserveCapacity(count)
        for _ in 0..<(count - songs.count) {
            result.append(songs.randomElement()!)
        }
        return result
    }

    // MARK: - Weighted by Recency

    private func weightedByRecency(_ songs: [Song]) -> [Song] {
        // Sort by lastPlayedDate ascending (nil = never played = first)
        // Then shuffle within tiers to add variety
        let sorted = songs.sorted { song1, song2 in
            let date1 = song1.lastPlayedDate ?? .distantPast
            let date2 = song2.lastPlayedDate ?? .distantPast
            return date1 < date2
        }
        return shuffleWithinTiers(sorted, tierSize: max(1, songs.count / 10))
    }

    // MARK: - Weighted by Play Count

    private func weightedByPlayCount(_ songs: [Song]) -> [Song] {
        // Sort by playCount ascending (0 plays = first)
        // Then shuffle within tiers
        let sorted = songs.sorted { $0.playCount < $1.playCount }
        return shuffleWithinTiers(sorted, tierSize: max(1, songs.count / 10))
    }

    private func shuffleWithinTiers(_ songs: [Song], tierSize: Int) -> [Song] {
        var result: [Song] = []
        var remaining = songs

        while !remaining.isEmpty {
            let tierEnd = min(tierSize, remaining.count)
            let tier = Array(remaining.prefix(tierEnd))
            remaining = Array(remaining.dropFirst(tierEnd))
            result.append(contentsOf: tier.shuffled())
        }

        return result
    }

    // MARK: - Artist Spacing

    private func artistSpacing(_ songs: [Song]) -> [Song] {
        guard songs.count > 1 else { return songs }

        // Group songs by artist
        var byArtist: [String: [Song]] = [:]
        for song in songs.shuffled() {
            byArtist[song.artist, default: []].append(song)
        }

        var result: [Song] = []
        var recentArtists: [String] = []
        let spacingWindow = min(3, byArtist.keys.count - 1)

        while result.count < songs.count {
            // Find artist not in recent window with songs remaining
            let availableArtist = byArtist.keys.first { artist in
                !recentArtists.suffix(spacingWindow).contains(artist) &&
                !(byArtist[artist]?.isEmpty ?? true)
            }

            // Fall back to any artist with songs if spacing impossible
            let chosenArtist = availableArtist ?? byArtist.keys.first { !(byArtist[$0]?.isEmpty ?? true) }

            guard let artist = chosenArtist,
                  var artistSongs = byArtist[artist],
                  !artistSongs.isEmpty else {
                break
            }

            let song = artistSongs.removeFirst()
            byArtist[artist] = artistSongs
            result.append(song)
            recentArtists.append(artist)
        }

        return result
    }
}
