import Foundation

@Observable
@MainActor
final class PlaylistDetailViewModel {
    private(set) var songs: [Song] = []
    private(set) var isLoading = true
    private(set) var hasMorePages = true
    private(set) var errorMessage: String?

    @ObservationIgnored private let musicService: MusicService
    @ObservationIgnored private let pageSize = 50
    @ObservationIgnored private var currentOffset = 0
    @ObservationIgnored private var isLoadingMore = false

    let playlistId: String
    let playlistName: String

    init(playlistId: String, playlistName: String, musicService: MusicService) {
        self.playlistId = playlistId
        self.playlistName = playlistName
        self.musicService = musicService
    }

    func loadInitialPage() async {
        guard songs.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        currentOffset = 0

        do {
            let page = try await musicService.fetchSongs(
                byPlaylistId: playlistId,
                limit: pageSize,
                offset: 0
            )
            songs = page.songs
            hasMorePages = page.hasMore
            currentOffset = page.songs.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func loadMorePages() async {
        guard hasMorePages, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let page = try await musicService.fetchSongs(
                byPlaylistId: playlistId,
                limit: pageSize,
                offset: currentOffset
            )
            songs.append(contentsOf: page.songs)
            hasMorePages = page.hasMore
            currentOffset += page.songs.count
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingMore = false
    }
}
