import ShflCore
import ShflDesign
import SwiftUI

/// The inspector column: what's playing, the wheel, and what plays next. One layout per state.
struct PlayingColumn: View {
    @Environment(ListeningSessionHost.self) private var sessionHost
    @State private var isShowingSession = false

    var body: some View {
        let timeline = sessionHost.timeline
        Group {
            switch (timeline.status, isShowingSession) {
            case (.idle, _):
                EmptyPlayer(timeline: timeline, isShowingSession: $isShowingSession)
            case (.active, false):
                ArtworkPlayer(timeline: timeline, isShowingSession: $isShowingSession)
            case (.ended, false):
                FinishedPlayer(timeline: timeline, isShowingSession: $isShowingSession)
            case (_, true):
                WholeSessionPlayer(timeline: timeline, isShowingSession: $isShowingSession)
            }
        }
        .padding(.horizontal, Spacing.s20)
        .padding(.bottom, Spacing.s14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .playerSurface()
        .tintedByArtwork(of: timeline.current)
        .focusedSceneValue(\.wholeSession, $isShowingSession)
        // There's no session to show once it clears, so the next one opens on the artwork.
        .onChange(of: timeline.status) { _, status in
            if status == .idle { isShowingSession = false }
        }
        .accessibilityIdentifier("mac.player")
    }
}

private struct ArtworkPlayer: View {
    let timeline: SessionTimeline
    @Binding var isShowingSession: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlayerHeader()
                SongArtwork(song: timeline.current, size: ArtworkSize.hero)
                    .elevation(.artworkLarge)
                SessionHeadline(timeline: timeline)
                    .padding(.top, Spacing.s16)
                PlaybackScrubber()
                    .padding(.top, Spacing.s16)
                TransportWheel(isShowingSession: $isShowingSession)
                    .padding(.top, Spacing.s8)
                UpNextSection(timeline: timeline)
                    .padding(.top, Spacing.s14)
            }
        }
        .scrollIndicators(.never)
    }
}

private struct WholeSessionPlayer: View {
    let timeline: SessionTimeline
    @Binding var isShowingSession: Bool

    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let copy = SessionCopy(timeline: timeline, play: sessionHost.intents.play)
        VStack(spacing: 0) {
            PlayerHeader()
            HStack(spacing: Spacing.s12) {
                SongArtwork(song: timeline.current, size: ArtworkSize.compact)
                    .elevation(.artworkSmall)
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(copy.title)
                        .font(.playerTitleCompact)
                    MarqueeText(copy.subtitle, alignment: .leading)
                        .font(.bodyText)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            if timeline.current != nil {
                PlaybackScrubber()
                    .padding(.top, Spacing.s16)
            }
            SessionList(timeline: timeline)
                .padding(.top, Spacing.s12)
                .frame(maxHeight: .infinity)
            TransportWheel(isShowingSession: $isShowingSession)
                .padding(.top, Spacing.s10)
        }
    }
}

private struct EmptyPlayer: View {
    let timeline: SessionTimeline
    @Binding var isShowingSession: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlayerHeader()
                ArtworkFrame(size: ArtworkSize.hero) { ArtworkPlaceholder() }
                    .elevation(.artworkLarge)
                SessionHeadline(timeline: timeline)
                    .padding(.top, Spacing.s16)
                IdleScrubber(isFilled: false)
                    .padding(.top, Spacing.s16)
                TransportWheel(isShowingSession: $isShowingSession)
                    .padding(.top, Spacing.s8)
                UpNextPlaceholder()
                    .padding(.top, Spacing.s14)
            }
        }
        .scrollIndicators(.never)
    }
}

private struct FinishedPlayer: View {
    let timeline: SessionTimeline
    @Binding var isShowingSession: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PlayerHeader()
                ArtworkFrame(size: ArtworkSize.hero) { ArtworkPlaceholder(systemImage: "checkmark.circle") }
                    .elevation(.artworkLarge)
                SessionHeadline(timeline: timeline)
                .padding(.top, Spacing.s16)
                IdleScrubber(isFilled: true)
                    .padding(.top, Spacing.s16)
                TransportWheel(isShowingSession: $isShowingSession)
                    .padding(.top, Spacing.s8)
                LastPlayedSection(timeline: timeline)
                    .padding(.top, Spacing.s14)
            }
        }
        .scrollIndicators(.never)
    }
}

extension FocusedValues {
    @Entry var wholeSession: Binding<Bool>?
    @Entry var isEditingText: Bool?
}
