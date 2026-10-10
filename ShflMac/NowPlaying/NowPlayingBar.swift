import ShflCore
import SwiftUI

struct NowPlayingBar: View {
    let makePlaybackClock: () -> PlaybackClock

    @Environment(ShufflePlayer.self) private var player

    var body: some View {
        HStack(spacing: 16) {
            NowPlayingArtwork(song: player.playbackState.currentSong)
            NowPlayingTitles(song: player.playbackState.currentSong, notice: player.operationNotice)
                .frame(minWidth: 140, maxWidth: 260, alignment: .leading)
            Spacer(minLength: 8)
            TransportButtons()
            PlaybackScrubber(makePlaybackClock: makePlaybackClock)
                .frame(minWidth: 200, maxWidth: 380)
            Spacer(minLength: 8)
            SelectedMeter()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
