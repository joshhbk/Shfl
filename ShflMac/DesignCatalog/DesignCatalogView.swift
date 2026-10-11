#if DEBUG
import ShflDesign
import SwiftUI

/// Every ShflDesign primitive in one window, in any theme and scheme. Help › Design Catalog.
struct DesignCatalogView: View {
    static let windowID = "design-catalog"

    @State private var theme = ShflTheme.pink
    @State private var scheme = ColorScheme.light
    @State private var isTinted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s20) {
                CatalogSection("Colour") { ColorSwatches() }
                CatalogSection("Type") { TypeSpecimens() }
                CatalogSection("Buttons") { ButtonSpecimens() }
                CatalogSection("Song list") { SongListSpecimen() }
                CatalogSection("Picks") { PicksSpecimen() }
                CatalogSection("Collections") { CollectionSpecimens() }
                CatalogSection("Empty states") { EmptyStateSpecimens() }
                CatalogSection("Player") {
                    HStack(alignment: .top, spacing: Spacing.s20) {
                        PlayerSpecimen()
                        EmptyPlayerSpecimen()
                    }
                }
            }
            .padding(Spacing.s20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .elevatedSurface()
        .environment(\.colorScheme, scheme)
        .shflTheme(theme)
        .artworkTint(isTinted ? CatalogSample.tone : nil)
        .toolbar {
            Picker("Theme", selection: $theme) {
                ForEach(ShflTheme.all) { Text($0.name).tag($0) }
            }
            Picker("Appearance", selection: $scheme) {
                Text("Light").tag(ColorScheme.light)
                Text("Dark").tag(ColorScheme.dark)
            }
            .pickerStyle(.segmented)
            Toggle("Artwork tint", isOn: $isTinted)
        }
        .navigationTitle("Design Catalog")
    }
}

struct DesignCatalogCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Design Catalog") { openWindow(id: DesignCatalogView.windowID) }
        }
    }
}

private struct CatalogSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s12) {
            Text(title).font(.playerTitle)
            content
        }
    }
}

private struct ColorSwatches: View {
    private let tokens: [(String, DesignColor)] = [
        ("surfaceContent", .surfaceContent), ("surfaceElevated", .surfaceElevated), ("quietFill", .quietFill),
        ("textPrimary", .textPrimary), ("textSecondary", .textSecondary), ("textTertiary", .textTertiary),
        ("accentFill", .accentFill), ("accentText", .accentText),
        ("playerBody", .playerBody), ("ink", .ink), ("inkSecondary", .inkSecondary),
        ("wheel", .wheel), ("wheelGlyph", .wheelGlyph),
        ("artworkPlaceholder", .artworkPlaceholder), ("hairline", .hairline),
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Spacing.s12)], spacing: Spacing.s12) {
            ForEach(tokens, id: \.0) { name, color in
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    RoundedRectangle(cornerRadius: CornerRadius.regular)
                        .fill(color)
                        .overlay { RoundedRectangle(cornerRadius: CornerRadius.regular).strokeBorder(.hairline) }
                        .frame(height: 44)
                    Text(name).font(.meta).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct TypeSpecimens: View {
    private let roles: [(String, Font)] = [
        ("playerTitle", .playerTitle), ("playerTitleCompact", .playerTitleCompact),
        ("cardTitle", .cardTitle), ("emptyStateTitle", .emptyStateTitle), ("sectionTitle", .sectionTitle),
        ("bodyEmphasis", .bodyEmphasis), ("bodyText", .bodyText), ("secondaryText", .secondaryText),
        ("rowTitle", .rowTitle), ("columnLabel", .columnLabel), ("meta", .meta), ("tag", .tag), ("keyHint", .keyHint),
    ]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.s16, verticalSpacing: Spacing.s8) {
            ForEach(roles, id: \.0) { name, font in
                GridRow {
                    Text(name).font(.meta).foregroundStyle(.secondary)
                    Text("Once in a Lifetime").font(font)
                }
            }
        }
    }
}

private struct ButtonSpecimens: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: Spacing.s12, verticalSpacing: Spacing.s12) {
            ForEach([ControlSize.small, .regular, .large], id: \.self) { size in
                GridRow {
                    Button("Shuffle Now") {}.buttonStyle(.primary)
                    Button("Autofill 30") {}.buttonStyle(.quiet)
                    Button("Shuffle Now") {}.buttonStyle(.primary).disabled(true)
                }
                .controlSize(size)
            }
        }
    }
}

private struct SongListSpecimen: View {
    @State private var picked: Set<Int> = [0, 2]

    private let columns: [ListColumn] = [.artwork, .title, .detail, .stat("plays", width: 48), .time, .accessory]

    var body: some View {
        VStack(spacing: 0) {
            ListColumns(columns) {
                Button("Title") {}.buttonStyle(.columnSort(isSorted: false)).listColumn(.title)
                ColumnLabel("Album").listColumn(.detail)
                Button("Plays") {}.buttonStyle(.columnSort(isSorted: true)).listColumn(.stat("plays", width: 48))
                ColumnLabel("Time").listColumn(.time)
            }
            .frame(height: 28)
            .padding(.horizontal, Spacing.s20)
            Divider()
            ForEach(Array(CatalogSample.library.enumerated()), id: \.offset) { index, song in
                ListColumns(columns) {
                    ArtworkFrame(size: ArtworkSize.songRow) { ArtworkPlaceholder() }
                        .listColumn(.artwork)
                    HStack(spacing: Spacing.s6) {
                        RowTitles(song.title, subtitle: song.artist).fixedSize()
                        if index == 2 { AccentTag("Next shuffle") }
                        Spacer(minLength: 0)
                    }
                    .listColumn(.title)
                    Text(song.album).font(.secondaryText).foregroundStyle(.secondary).listColumn(.detail)
                    Text(song.plays, format: .number).font(.secondaryText.monospacedDigit()).foregroundStyle(.secondary).listColumn(.stat("plays", width: 48))
                    Text("3:04").font(.secondaryText.monospacedDigit()).foregroundStyle(.secondary).listColumn(.time)
                    Toggle("Pick \(song.title)", isOn: isPicked(index))
                        .toggleStyle(.pick)
                        .disabled(index == 3)
                        .listColumn(.accessory)
                }
                .frame(height: 46)
                .padding(.horizontal, Spacing.s20)
                .background(index == 1 ? AnyShapeStyle(.accentFill) : AnyShapeStyle(.clear))
                .environment(\.backgroundProminence, index == 1 ? .increased : .standard)
                Divider()
            }
            FloatingBar {
                Text("3 selected")
                Button {} label: {
                    HStack(spacing: Spacing.s8) {
                        Text("Add to Picks")
                        KeyHint("↩")
                    }
                }
                .buttonStyle(.primary)
            }
            .padding(Spacing.s16)
        }
        .frame(width: 720)
        .contentSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.card))
    }

    private func isPicked(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { picked.contains(index) },
            set: { isOn in
                if isOn { picked.insert(index) } else { picked.remove(index) }
            }
        )
    }
}

private struct PicksSpecimen: View {
    private let tones: [Color] = [
        Color(red: 0.12, green: 0.16, blue: 0.35), Color(red: 0.94, green: 0.90, blue: 0.82), Color(red: 0.48, green: 0.25, blue: 0.63),
        Color(red: 0.85, green: 0.26, blue: 0.18), Color(red: 0.18, green: 0.45, blue: 0.77),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s20) {
            VStack(alignment: .leading, spacing: Spacing.s14) {
                CountFraction(46, of: 120)
                Tray(capacity: 120, marks: [50, 100, 120]) { index in
                    if index < 46 {
                        PickedTile(tone: index == 7 ? nil : tones[index % tones.count]).tileRing(index >= 43)
                    } else {
                        EmptyTile().milestoneOutline([50, 100, 120].contains(index + 1))
                    }
                }
            }
            .frame(width: 260)
            VStack(alignment: .leading, spacing: Spacing.s14) {
                CountFraction(37, of: 120)
                CapacityRule(37, of: 120, marks: [50, 100, 120])
            }
            .frame(width: 260)
        }
        .padding(Spacing.s20)
        .paneSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.card))
    }
}

private struct CollectionSpecimens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            CollectionHeader("Beach House", subtitle: "41 songs") {
                RoundArtworkFrame(size: ArtworkSize.collection) { MonogramArtwork("Beach House") }
            } actions: {
                Button("Add All") {}.buttonStyle(.primary)
            }
            .frame(width: 560)
            .contentSurface()
            .clipShape(.rect(cornerRadius: CornerRadius.card))
            HStack(spacing: Spacing.s12) {
                ForEach(["Beach House", "Clairo", "Fontaines D.C.", "Lorde", "Mazzy Star", "070 Shake"], id: \.self) { name in
                    RoundArtworkFrame(size: ArtworkSize.songRow) { MonogramArtwork(name) }
                }
            }
        }
    }
}

private struct EmptyStateSpecimens: View {
    var body: some View {
        HStack(spacing: Spacing.s20) {
            EmptyState("No songs match “radiohed”", message: "Check the spelling, or try the same search in Artists.") {
                Button("Clear Search") {}
                Button("Search Artists") {}
            }
            .frame(width: 340, height: 220)
            .contentSurface()
            .clipShape(.rect(cornerRadius: CornerRadius.card))
            EmptyState("No songs in your library yet", message: "Shuffled plays what’s in your Apple Music library. Add music in the Music app and it shows up here.") {
                EmptyStateSymbol("music.note")
            } actions: {
                Button("Open Music") {}
            }
            .frame(width: 340, height: 220)
            .contentSurface()
            .clipShape(.rect(cornerRadius: CornerRadius.card))
        }
    }
}

private struct PlayerSpecimen: View {
    @State private var position = 72.0
    @State private var isShowingSession = false
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 0) {
            ArtworkFrame(size: ArtworkSize.hero) { ArtworkPlaceholder() }
                .elevation(.artworkLarge)
            Text(CatalogSample.current.title)
                .font(.playerTitle)
                .padding(.top, Spacing.s16)
            MarqueeText("\(CatalogSample.current.artist), Julien Baker & Lucy Dacus · Punisher (Deluxe Edition)")
                .font(.bodyText)
                .foregroundStyle(.secondary)
                .padding(.top, Spacing.s2)

            Scrubber(value: $position, in: 0...184, step: 5)
                .padding(.top, Spacing.s16)
            HStack {
                Text("1:12")
                Spacer()
                Text("−1:52")
            }
            .font(.secondaryText.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.top, Spacing.s8)

            ClickWheel(onKeyboardPress: { if $0 == .center { isPlaying.toggle() } }) {
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    isPlaying.toggle()
                }
            } top: {
                Button("Shuffle Again", systemImage: "shuffle") {}
            } leading: {
                Button("Previous", systemImage: "backward.fill") {}
            } trailing: {
                Button("Next", systemImage: "forward.fill") {}
            } bottom: {
                Toggle("Show the Whole Session", systemImage: "list.bullet", isOn: $isShowingSession)
            }
            .padding(.top, Spacing.s8)

            SectionHeader("Up Next")
                .padding(.top, Spacing.s14)
            ForEach(Array(CatalogSample.upNext.enumerated()), id: \.offset) { offset, song in
                CompactRow {
                    RowIndex(24 + offset)
                    ArtworkFrame(size: ArtworkSize.listRow) { ArtworkPlaceholder() }
                    RowTitles(song.title, subtitle: song.artist)
                    if offset == 1 {
                        OutlinedTag("Unpicked")
                    }
                }
                .rowHighlight(offset == 0)
            }
        }
        .padding(.horizontal, Spacing.s20)
        .padding(.vertical, Spacing.s16)
        .frame(width: 340)
        .playerSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.card))
    }
}

private struct EmptyPlayerSpecimen: View {
    var body: some View {
        VStack(spacing: Spacing.s20) {
            HStack(spacing: Spacing.s10) {
                Button("Previous", systemImage: "backward.fill") {}.buttonStyle(.transport)
                Button("Pause", systemImage: "pause.fill") {}.buttonStyle(.transportPrimary)
                Button("Next", systemImage: "forward.fill") {}.buttonStyle(.transport)
            }
            .padding(Spacing.s12)
            .playerSurface()
            .clipShape(.rect(cornerRadius: CornerRadius.card))
            VStack(spacing: 0) {
                Button("Open Shuffled") {}.buttonStyle(.menuRow)
                Button("Quit Shuffled") {}.buttonStyle(.menuRow)
            }
            .padding(Spacing.s6)
            .elevatedSurface()
            .clipShape(.rect(cornerRadius: CornerRadius.panel))
            OutlinedTag("Unpicked")
        }
        .padding(Spacing.s20)
        .frame(width: 300)
        .elevatedSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.card))
    }
}

private enum CatalogSample {
    static let tone = Color.Resolved(red: 0.12, green: 0.16, blue: 0.35)
    static let current = (title: "Kyoto", artist: "Phoebe Bridgers")
    static let library: [(title: String, artist: String, album: String, plays: Int)] = [
        ("Kyoto", "Phoebe Bridgers", "Punisher", 212),
        ("Green Light", "Lorde", "Melodrama", 169),
        ("Starburster", "Fontaines D.C.", "Romance", 151),
        ("Alright", "Kendrick Lamar", "To Pimp a Butterfly", 131),
    ]
    static let upNext: [(title: String, artist: String)] = [
        ("Kyoto", "Phoebe Bridgers"),
        ("Red Eyes", "The War on Drugs"),
        ("Once in a Lifetime", "Talking Heads"),
        ("Let It Happen", "Tame Impala"),
    ]
}
#endif
