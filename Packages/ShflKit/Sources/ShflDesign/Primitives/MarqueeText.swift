import SwiftUI

/// One line of text. When it doesn't fit it rests with an ellipsis, then every few seconds scrolls
/// through the whole line and loops back to the start, like Apple Music. Reduce Motion keeps it still.
public struct MarqueeText: View {
    private let text: String
    private let alignment: Alignment

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isScrolling = false

    public init(_ text: String, alignment: Alignment = .center) {
        self.text = text
        self.alignment = alignment
    }

    public var body: some View {
        let overflows = Self.overflows(textWidth: textWidth, availableWidth: availableWidth)
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(isScrolling ? 0 : 1)
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay(alignment: .leading) {
                if isScrolling {
                    HStack(spacing: Self.gap) {
                        Text(text)
                        Text(text)
                    }
                    .fixedSize()
                    .offset(x: offset)
                    .mask(alignment: .leading) { EdgeFade().frame(width: availableWidth) }
                }
            }
            .clipped()
            .background {
                Text(text)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
            .task(id: ScrollKey(text: text, overflows: overflows, reduceMotion: reduceMotion)) {
                await scroll(enabled: overflows && !reduceMotion)
            }
            .help(overflows ? text : "")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private func scroll(enabled: Bool) async {
        isScrolling = false
        offset = 0
        guard enabled else { return }
        let distance = textWidth + Self.gap
        let duration = Self.scrollDuration(for: distance)
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.restDuration)
            guard !Task.isCancelled else { return }
            isScrolling = true
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            isScrolling = false
            offset = 0
        }
    }

    static let gap: CGFloat = 40
    static let pointsPerSecond: Double = 30
    static let restDuration = Duration.seconds(3)

    static func overflows(textWidth: CGFloat, availableWidth: CGFloat) -> Bool {
        availableWidth > 0 && textWidth > availableWidth + 0.5
    }

    static func scrollDuration(for distance: CGFloat) -> Double {
        Double(distance) / pointsPerSecond
    }
}

private struct ScrollKey: Equatable {
    let text: String
    let overflows: Bool
    let reduceMotion: Bool
}

/// Softens both edges while the text is moving, so it slides in and out rather than being cut.
private struct EdgeFade: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
