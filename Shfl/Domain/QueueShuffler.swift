import Foundation

nonisolated struct QueueShuffler: Sendable {
    let algorithm: ShuffleAlgorithm
    let seed: UInt64

    init(
        algorithm: ShuffleAlgorithm,
        seed: UInt64 = UInt64.random(in: .min ... .max)
    ) {
        self.algorithm = algorithm
        self.seed = seed
    }

    func shuffle(_ songs: [Song], count: Int? = nil) -> [Song] {
        guard !songs.isEmpty else { return [] }
        var random = SeededRandomNumberGenerator(seed: seed)

        switch algorithm {
        case .pureRandom:
            return pureRandom(songs, count: count ?? songs.count, random: &random)
        case .noRepeat:
            return shuffled(songs, random: &random)
        case .weightedByRecency:
            return weightedByRecency(songs, random: &random)
        case .weightedByPlayCount:
            return weightedByPlayCount(songs, random: &random)
        case .artistSpacing:
            return artistSpacing(songs, random: &random)
        }
    }

    // MARK: - Pure Random

    private func pureRandom(
        _ songs: [Song],
        count: Int,
        random: inout SeededRandomNumberGenerator
    ) -> [Song] {
        guard count > 0 else { return [] }

        if count <= songs.count {
            return Array(shuffled(songs, random: &random).prefix(count))
        }

        var result = shuffled(songs, random: &random)
        result.reserveCapacity(count)
        for _ in 0..<(count - songs.count) {
            result.append(songs[randomIndex(upperBound: songs.count, random: &random)])
        }
        return result
    }

    // MARK: - Weighted by Recency

    private func weightedByRecency(
        _ songs: [Song],
        random: inout SeededRandomNumberGenerator
    ) -> [Song] {
        songs
            .map { song in
                (
                    song: song,
                    lastPlayedDate: song.lastPlayedDate ?? .distantPast,
                    tieBreaker: random.next()
                )
            }
            .sorted { left, right in
                if left.lastPlayedDate != right.lastPlayedDate {
                    return left.lastPlayedDate < right.lastPlayedDate
                }
                if left.tieBreaker != right.tieBreaker {
                    return left.tieBreaker < right.tieBreaker
                }
                return left.song.id < right.song.id
            }
            .map(\.song)
    }

    // MARK: - Weighted by Play Count

    private func weightedByPlayCount(
        _ songs: [Song],
        random: inout SeededRandomNumberGenerator
    ) -> [Song] {
        songs
            .map { song in
                (
                    song: song,
                    playCount: song.playCount,
                    tieBreaker: random.next()
                )
            }
            .sorted { left, right in
                if left.playCount != right.playCount {
                    return left.playCount < right.playCount
                }
                if left.tieBreaker != right.tieBreaker {
                    return left.tieBreaker < right.tieBreaker
                }
                return left.song.id < right.song.id
            }
            .map(\.song)
    }

    // MARK: - Artist Spacing

    private func artistSpacing(
        _ songs: [Song],
        random: inout SeededRandomNumberGenerator
    ) -> [Song] {
        guard songs.count > 1 else { return songs }

        var byArtist: [String: [Song]] = [:]
        for song in shuffled(songs, random: &random) {
            byArtist[song.artist, default: []].append(song)
        }
        let artistOrder = shuffled(Array(byArtist.keys).sorted(), random: &random)

        var result: [Song] = []
        var recentArtists: [String] = []
        let spacingWindow = min(3, byArtist.keys.count - 1)
        var nextArtistOffset = 0

        while result.count < songs.count {
            let rotatedArtists = Array(artistOrder[nextArtistOffset...]) + Array(artistOrder[..<nextArtistOffset])
            let availableArtist = rotatedArtists.first { artist in
                !recentArtists.suffix(spacingWindow).contains(artist)
                    && !(byArtist[artist]?.isEmpty ?? true)
            }
            let chosenArtist = availableArtist
                ?? rotatedArtists.first { !(byArtist[$0]?.isEmpty ?? true) }

            guard let artist = chosenArtist,
                  var artistSongs = byArtist[artist],
                  !artistSongs.isEmpty else {
                break
            }

            let song = artistSongs.removeFirst()
            byArtist[artist] = artistSongs
            result.append(song)
            recentArtists.append(artist)
            if let selectedIndex = artistOrder.firstIndex(of: artist) {
                nextArtistOffset = (selectedIndex + 1) % artistOrder.count
            }
        }

        return result
    }

    private func shuffled<Element>(
        _ elements: [Element],
        random: inout SeededRandomNumberGenerator
    ) -> [Element] {
        guard elements.count > 1 else { return elements }

        var result = elements
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let swapIndex = randomIndex(upperBound: index + 1, random: &random)
            guard index != swapIndex else { continue }
            result.swapAt(index, swapIndex)
        }
        return result
    }

    private func randomIndex(
        upperBound: Int,
        random: inout SeededRandomNumberGenerator
    ) -> Int {
        Int(random.next() % UInt64(upperBound))
    }
}
