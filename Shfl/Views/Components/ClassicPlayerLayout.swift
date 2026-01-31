import SwiftUI

/// The classic iPod Shuffle player layout, composing PlayerTopBar, SongInfoDisplay, and PlayerControlsPanel
struct ClassicPlayerLayout: View {
    let playbackState: PlaybackState
    let isControlsDisabled: Bool
    let currentTime: TimeInterval
    let duration: TimeInterval
    let highlightOffset: CGPoint
    let actions: PlayerActions
    let showError: Bool
    let errorMessage: String
    let safeAreaInsets: EdgeInsets
    let onDismissError: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if showError {
                ErrorBanner(message: errorMessage, onDismiss: onDismissError)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            PlayerTopBar(
                onAddTapped: actions.onAdd,
                onSettingsTapped: actions.onSettings,
                topPadding: showError ? 16 : safeAreaInsets.top + 16
            )

            Spacer()

            // Song info panel - brushed metal
            ShuffleBodyView(highlightOffset: highlightOffset, height: 120) {
                SongInfoDisplay(
                    playbackState: playbackState,
                    currentTime: currentTime,
                    duration: duration
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Controls panel
            PlayerControlsPanel(
                isPlaying: playbackState.isPlaying,
                isDisabled: isControlsDisabled,
                highlightOffset: highlightOffset,
                actions: actions
            )
            .padding(.horizontal, 20)
            .padding(.bottom, safeAreaInsets.bottom + 12)
        }
        .animation(.easeInOut(duration: 0.2), value: showError)
    }
}
