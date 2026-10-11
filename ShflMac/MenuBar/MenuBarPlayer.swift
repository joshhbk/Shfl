import AppKit
import ShflCore
import ShflDesign
import SwiftUI

/// The menu bar item: a disc and the song that's playing.
struct MenuBarLabel: View {
    let sessionHost: ListeningSessionHost

    var body: some View {
        let song = sessionHost.timeline.current
        HStack(spacing: Spacing.s4) {
            Image(systemName: "opticaldisc")
            if let song {
                Text(song.title)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(song.map { "Shuffled. Playing \($0.title) by \($0.artist)" } ?? "Shuffled")
    }
}

/// The menu bar popover: now playing, the picks, and the app's commands.
struct MenuBarPlayer: View {
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        VStack(spacing: 0) {
            MenuBarNowPlaying()
                .padding(.top, Spacing.s14)
                .padding(.horizontal, Spacing.s16)
                .padding(.bottom, Spacing.s12)
                .playerSurface()
                .tintedByArtwork(of: sessionHost.timeline.current)
            MenuBarPicks()
                .padding(Spacing.s14)
                .overlay(alignment: .bottom) { Rectangle().fill(.hairline).frame(height: 1) }
            MenuBarCommands()
                .padding(Spacing.s6)
        }
        .frame(width: 330)
        .elevatedSurface()
    }
}

private struct MenuBarNowPlaying: View {
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let timeline = sessionHost.timeline
        let copy = SessionCopy(timeline: timeline, play: sessionHost.intents.play)
        VStack(spacing: Spacing.s10) {
            HStack(spacing: Spacing.s12) {
                SongArtwork(song: timeline.current, size: ArtworkSize.menuBar)
                    .elevation(.artworkSmall)
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(copy.title)
                        .font(.playerTitleCompact)
                    MarqueeText(copy.subtitle, alignment: .leading)
                        .font(.secondaryText)
                        .foregroundStyle(.secondary)
                    if let position = timeline.position {
                        Text("\(position) of \(timeline.songCount)")
                            .font(.meta.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            PlaybackScrubber()
            MenuBarTransport()
        }
    }
}

private struct MenuBarTransport: View {
    @Environment(ListeningSessionHost.self) private var sessionHost

    var body: some View {
        let play = sessionHost.intents.play
        HStack(spacing: Spacing.s10) {
            Button("Previous", systemImage: "backward.fill") {
                Task { await sessionHost.skipToPrevious() }
            }
            .buttonStyle(.transport)
            .disabled(!sessionHost.canSkip)
            Button(play.title, systemImage: play.systemImage) {
                Task { await sessionHost.togglePlayback() }
            }
            .buttonStyle(.transportPrimary)
            .accessibilityHint(play.accessibilityHint ?? "")
            .disabled(sessionHost.isStartingSession)
            Button("Next", systemImage: "forward.fill") {
                Task { await sessionHost.skipToNext() }
            }
            .buttonStyle(.transport)
            .disabled(!sessionHost.canSkip)
        }
    }
}

struct MenuBarPicks: View {
    @Environment(ListeningSessionHost.self) private var sessionHost
    @Environment(DraftEditing.self) private var drafting

    var body: some View {
        let draft = drafting.draft
        let timeline = sessionHost.timeline
        VStack(alignment: .leading, spacing: Spacing.s10) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s6) {
                Text("Picks").font(.bodyEmphasis)
                Text(draft.songCount, format: .number).font(.cardTitle.monospacedDigit())
                Text("/ \(draft.capacity)").font(.columnLabel.monospacedDigit()).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if let summary = Self.summary(of: timeline.changes) {
                    Text(summary)
                        .font(.columnLabel)
                        .foregroundStyle(.accentText)
                }
            }
            HStack(spacing: Spacing.s8) {
                Button {
                    Task { await sessionHost.startFreshShuffle(autofillingEmptyDraft: true) }
                } label: {
                    Text(sessionHost.intents.shuffle.title).frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(sessionHost.isStartingSession)
                Button("Autofill \(draft.remainingCapacity)") {
                    Task { await drafting.autofill() }
                }
                .buttonStyle(.quiet)
                .disabled(!drafting.canAutofill)
            }
            .controlSize(.small)
        }
    }

    static func summary(of changes: DraftChanges) -> String? {
        let added = changes.joiningNextShuffle.count
        let removed = changes.leftPool.count
        switch (added, removed, changes.algorithmChanged) {
        case (0, 0, false): return nil
        case (0, 0, true): return "New shuffle style"
        default: return "\(added) added, \(removed) removed"
        }
    }
}

private struct MenuBarCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Button(action: showMainWindow) { CommandLabel("Open Shuffled") }
            MenuDivider()
            Button { NSApp.terminate(nil) } label: { CommandLabel("Quit Shuffled", shortcut: "⌘Q") }
        }
        .buttonStyle(.menuRow)
    }

    private func showMainWindow() {
        openWindow(id: ShflMacApp.mainWindowID)
        NSApp.activate()
    }
}

private struct CommandLabel: View {
    let title: String
    let shortcut: String?

    init(_ title: String, shortcut: String? = nil) {
        self.title = title
        self.shortcut = shortcut
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: Spacing.s8)
            if let shortcut {
                Text(shortcut).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(.hairline)
            .frame(height: 1)
            .padding(.vertical, Spacing.s4)
            .padding(.horizontal, Spacing.s10)
    }
}
