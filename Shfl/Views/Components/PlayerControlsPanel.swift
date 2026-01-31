import SwiftUI

/// Click wheel controls wrapped in a brushed metal panel
struct PlayerControlsPanel: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let highlightOffset: CGPoint
    let actions: PlayerActions

    var body: some View {
        ShuffleBodyView(highlightOffset: highlightOffset) {
            ClickWheelView(
                isPlaying: isPlaying,
                onPlayPause: actions.onPlayPause,
                onSkipForward: actions.onSkipForward,
                onSkipBack: actions.onSkipBack,
                onVolumeUp: { VolumeController.increaseVolume() },
                onVolumeDown: { VolumeController.decreaseVolume() },
                highlightOffset: highlightOffset,
                scale: 0.6
            )
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.6 : 1.0)
        }
    }
}
