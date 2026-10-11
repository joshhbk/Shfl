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
            VStack(alignment: .leading, spacing: Spacing.s32) {
                CatalogSection("Colour") { ColorSwatches() }
                CatalogSection("Type") { TypeSpecimens() }
                CatalogSection("Buttons") { ButtonSpecimens() }
                CatalogSection("Player") {
                    HStack(alignment: .top, spacing: Spacing.s24) {
                        PlayerSpecimen()
                        EmptyPlayerSpecimen()
                    }
                }
            }
            .padding(Spacing.s24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentSurface()
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
            Text(title).font(.heading)
            content
        }
    }
}

private struct ColorSwatches: View {
    private let tokens: [(String, DesignColor)] = [
        ("surfaceWindow", .surfaceWindow), ("surfaceContent", .surfaceContent),
        ("surfaceElevated", .surfaceElevated), ("surfaceSidebar", .surfaceSidebar),
        ("surfacePane", .surfacePane), ("quietFill", .quietFill), ("emptySlot", .emptySlot),
        ("textPrimary", .textPrimary), ("textSecondary", .textSecondary), ("textTertiary", .textTertiary),
        ("accentFill", .accentFill), ("accentText", .accentText), ("accentSoft", .accentSoft),
        ("playerBody", .playerBody), ("ink", .ink), ("inkSecondary", .inkSecondary),
        ("warning", .warning), ("success", .success), ("successText", .successText),
        ("wheel", .wheel), ("wheelGlyph", .wheelGlyph), ("chrome", .chrome),
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
        ("display", .display), ("heading", .heading), ("count", .count), ("playerTitle", .playerTitle),
        ("playerTitleCompact", .playerTitleCompact), ("emptyStateTitle", .emptyStateTitle),
        ("cardTitle", .cardTitle), ("paneTitle", .paneTitle), ("sectionTitle", .sectionTitle),
        ("bodyEmphasis", .bodyEmphasis), ("bodyText", .bodyText), ("secondaryText", .secondaryText),
        ("rowTitle", .rowTitle), ("columnLabel", .columnLabel), ("meta", .meta), ("tag", .tag),
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
                    Button("Shuffle Again") {}.buttonStyle(.outline)
                    Button("Autofill 30") {}.buttonStyle(.quiet)
                    Button("Shuffle Now") {}.buttonStyle(.primary).disabled(true)
                }
                .controlSize(size)
            }
        }
    }
}

private struct PlayerSpecimen: View {
    @State private var position = 72.0
    @State private var isShowingSession = false
    @State private var isPlaying = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Playing").font(.paneTitle)
                Text("23 of 86").font(.secondaryText.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                PillToolbar {
                    Button("Open Mini Player", systemImage: "rectangle.inset.bottomright.filled") {}
                    Button("Settings", systemImage: "gearshape") {}
                }
            }
            .frame(height: 52)

            ArtworkFrame(size: ArtworkSize.hero) { ArtworkPlaceholder() }
                .elevation(.artworkLarge)
            Text(CatalogSample.current.title)
                .font(.playerTitle)
                .padding(.top, Spacing.s16)
            Text("\(CatalogSample.current.artist) · Punisher")
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

            ClickWheel {
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

            SectionHeader("Up Next") { Text("Shuffled 2:14 PM · fixed order") }
                .padding(.top, Spacing.s14)
            ForEach(Array(CatalogSample.upNext.enumerated()), id: \.offset) { offset, song in
                CompactRow {
                    RowIndex(24 + offset)
                    ArtworkFrame(size: ArtworkSize.listRow) { ArtworkPlaceholder() }
                    RowTitles(song.title, subtitle: song.artist)
                    if offset == 1 {
                        OutlinedTag("Left pool")
                    }
                    RowDetail("3:04")
                }
                .rowHighlight(offset == 0)
            }
        }
        .padding(.horizontal, Spacing.s20)
        .padding(.bottom, Spacing.s14)
        .frame(width: 340)
        .playerSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.card))
    }
}

private struct EmptyPlayerSpecimen: View {
    var body: some View {
        VStack(spacing: Spacing.s24) {
            EmptyState("Just press Play", message: "With an empty pool, Play fills it with 120 random songs from your library, then shuffles.") {
                Button("Autofill and Shuffle") {}.buttonStyle(.primary)
            }
            HStack(spacing: Spacing.s8) {
                SoftTag("Next shuffle")
                OutlinedTag("Left pool")
            }
        }
        .padding(Spacing.s20)
        .frame(width: 300)
        .paneSurface()
        .clipShape(.rect(cornerRadius: CornerRadius.card))
    }
}

private enum CatalogSample {
    static let tone = Color.Resolved(red: 0.12, green: 0.16, blue: 0.35)
    static let current = (title: "Kyoto", artist: "Phoebe Bridgers")
    static let upNext: [(title: String, artist: String)] = [
        ("Kyoto", "Phoebe Bridgers"),
        ("Red Eyes", "The War on Drugs"),
        ("Once in a Lifetime", "Talking Heads"),
        ("Let It Happen", "Tame Impala"),
    ]
}
#endif
