import SwiftUI

enum PlayPauseMotionPreset: String, CaseIterable {
    case tight
    case soft
    case mechanical
}

struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void
    let theme: ShuffleTheme
    var motionPreset: PlayPauseMotionPreset = .soft
    var scale: CGFloat = 1.0

    @State private var isPressed = false

    private var buttonSize: CGFloat { 150 * scale }
    private var iconSize: CGFloat { 40 * scale }

    private var buttonBackgroundColor: Color {
        theme.bodyGradientTop
    }

    private var iconColor: Color {
        theme.centerButtonIconColor
    }

    private var iconAnimation: Animation {
        switch motionPreset {
        case .tight:
            return .spring(response: 0.24, dampingFraction: 0.88, blendDuration: 0.04)
        case .soft:
            return .spring(response: 0.34, dampingFraction: 0.76, blendDuration: 0.08)
        case .mechanical:
            return .interactiveSpring(response: 0.17, dampingFraction: 0.95, blendDuration: 0)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(buttonBackgroundColor)
                .frame(width: buttonSize, height: buttonSize)
                .shadow(
                    color: .black.opacity(0.1),
                    radius: isPressed ? ClickWheelFeedback.centerPressedShadowRadius : ClickWheelFeedback.centerNormalShadowRadius,
                    x: 0,
                    y: isPressed ? ClickWheelFeedback.centerPressedShadowY : ClickWheelFeedback.centerNormalShadowY
                )

            PlayPauseGlyph(progress: isPlaying ? 1 : 0, preset: motionPreset)
                .fill(iconColor)
                .frame(width: iconSize, height: iconSize)
                .animation(iconAnimation, value: isPlaying)
        }
        .scaleEffect(isPressed ? ClickWheelFeedback.centerPressScale : 1.0)
        .animation(.spring(response: ClickWheelFeedback.springResponse, dampingFraction: ClickWheelFeedback.springDampingFraction), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed {
                        isPressed = true
                    }
                }
                .onEnded { value in
                    isPressed = false
                    // Only fire action if release was within bounds
                    let bounds = CGRect(x: 0, y: 0, width: buttonSize, height: buttonSize)
                    if bounds.contains(value.location) {
                        HapticFeedback.medium.trigger()
                        action()
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            action()
        }
    }
}

private struct PlayPauseGlyph: Shape {
    var progress: CGFloat
    var preset: PlayPauseMotionPreset

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get {
            AnimatablePair(progress, CGFloat(Self.presetIndex(preset)))
        }
        set {
            progress = newValue.first
            preset = Self.indexToPreset(Int(newValue.second.rounded()))
        }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(max(progress, 0), 1)
        let shape = PlayPauseMorphPreset.forPreset(preset)
        let left = shape.playLeft.interpolated(to: shape.pauseLeft, t: t)
        let right = shape.playRight.interpolated(to: shape.pauseRight, t: t)

        var path = Path()
        path.addPath(left.path(in: rect))
        path.addPath(right.path(in: rect))
        return path
    }

    private static func presetIndex(_ preset: PlayPauseMotionPreset) -> Int {
        switch preset {
        case .tight: 0
        case .soft: 1
        case .mechanical: 2
        }
    }

    private static func indexToPreset(_ index: Int) -> PlayPauseMotionPreset {
        switch index {
        case 1: .soft
        case 2: .mechanical
        default: .tight
        }
    }
}

private struct PlayPauseMorphPreset {
    let playLeft: MorphQuad
    let pauseLeft: MorphQuad
    let playRight: MorphQuad
    let pauseRight: MorphQuad

    static func forPreset(_ preset: PlayPauseMotionPreset) -> PlayPauseMorphPreset {
        switch preset {
        case .tight:
            return .tight
        case .soft:
            return .soft
        case .mechanical:
            return .mechanical
        }
    }

    private static let tight = PlayPauseMorphPreset(
        playLeft: MorphQuad(
            p0: CGPoint(x: 0.18, y: 0.14),
            p1: CGPoint(x: 0.46, y: 0.293),
            p2: CGPoint(x: 0.46, y: 0.707),
            p3: CGPoint(x: 0.18, y: 0.86)
        ),
        pauseLeft: MorphQuad(
            p0: CGPoint(x: 0.20, y: 0.16),
            p1: CGPoint(x: 0.42, y: 0.16),
            p2: CGPoint(x: 0.42, y: 0.84),
            p3: CGPoint(x: 0.20, y: 0.84)
        ),
        playRight: MorphQuad(
            p0: CGPoint(x: 0.46, y: 0.293),
            p1: CGPoint(x: 0.84, y: 0.50),
            p2: CGPoint(x: 0.84, y: 0.50),
            p3: CGPoint(x: 0.46, y: 0.707)
        ),
        pauseRight: MorphQuad(
            p0: CGPoint(x: 0.60, y: 0.16),
            p1: CGPoint(x: 0.82, y: 0.16),
            p2: CGPoint(x: 0.82, y: 0.84),
            p3: CGPoint(x: 0.60, y: 0.84)
        )
    )

    private static let soft = PlayPauseMorphPreset(
        playLeft: MorphQuad(
            p0: CGPoint(x: 0.22, y: 0.17),
            p1: CGPoint(x: 0.47, y: 0.305),
            p2: CGPoint(x: 0.47, y: 0.695),
            p3: CGPoint(x: 0.22, y: 0.83)
        ),
        pauseLeft: MorphQuad(
            p0: CGPoint(x: 0.24, y: 0.17),
            p1: CGPoint(x: 0.43, y: 0.17),
            p2: CGPoint(x: 0.43, y: 0.83),
            p3: CGPoint(x: 0.24, y: 0.83)
        ),
        playRight: MorphQuad(
            p0: CGPoint(x: 0.47, y: 0.305),
            p1: CGPoint(x: 0.78, y: 0.50),
            p2: CGPoint(x: 0.78, y: 0.50),
            p3: CGPoint(x: 0.47, y: 0.695)
        ),
        pauseRight: MorphQuad(
            p0: CGPoint(x: 0.57, y: 0.17),
            p1: CGPoint(x: 0.76, y: 0.17),
            p2: CGPoint(x: 0.76, y: 0.83),
            p3: CGPoint(x: 0.57, y: 0.83)
        )
    )

    private static let mechanical = PlayPauseMorphPreset(
        playLeft: MorphQuad(
            p0: CGPoint(x: 0.14, y: 0.12),
            p1: CGPoint(x: 0.44, y: 0.285),
            p2: CGPoint(x: 0.44, y: 0.715),
            p3: CGPoint(x: 0.14, y: 0.88)
        ),
        pauseLeft: MorphQuad(
            p0: CGPoint(x: 0.16, y: 0.14),
            p1: CGPoint(x: 0.38, y: 0.14),
            p2: CGPoint(x: 0.38, y: 0.86),
            p3: CGPoint(x: 0.16, y: 0.86)
        ),
        playRight: MorphQuad(
            p0: CGPoint(x: 0.44, y: 0.285),
            p1: CGPoint(x: 0.90, y: 0.50),
            p2: CGPoint(x: 0.90, y: 0.50),
            p3: CGPoint(x: 0.44, y: 0.715)
        ),
        pauseRight: MorphQuad(
            p0: CGPoint(x: 0.62, y: 0.14),
            p1: CGPoint(x: 0.84, y: 0.14),
            p2: CGPoint(x: 0.84, y: 0.86),
            p3: CGPoint(x: 0.62, y: 0.86)
        )
    )
}

private struct MorphQuad {
    let p0: CGPoint
    let p1: CGPoint
    let p2: CGPoint
    let p3: CGPoint

    func interpolated(to target: MorphQuad, t: CGFloat) -> MorphQuad {
        MorphQuad(
            p0: p0.interpolated(to: target.p0, t: t),
            p1: p1.interpolated(to: target.p1, t: t),
            p2: p2.interpolated(to: target.p2, t: t),
            p3: p3.interpolated(to: target.p3, t: t)
        )
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: denormalize(p0, in: rect))
        path.addLine(to: denormalize(p1, in: rect))
        path.addLine(to: denormalize(p2, in: rect))
        path.addLine(to: denormalize(p3, in: rect))
        path.closeSubpath()
        return path
    }

    private func denormalize(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.minY + point.y * rect.height
        )
    }
}

private extension CGPoint {
    func interpolated(to target: CGPoint, t: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (target.x - x) * t,
            y: y + (target.y - y) * t
        )
    }
}

#Preview("Pink Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .pink)
        PlayPauseButton(isPlaying: true, action: {}, theme: .pink)
    }
    .padding()
    .background(ShuffleTheme.pink.bodyGradient)
}

#Preview("Silver Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .silver)
        PlayPauseButton(isPlaying: true, action: {}, theme: .silver)
    }
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
}

#Preview("Blue Theme") {
    VStack(spacing: 40) {
        PlayPauseButton(isPlaying: false, action: {}, theme: .blue)
        PlayPauseButton(isPlaying: true, action: {}, theme: .blue)
    }
    .padding()
    .background(ShuffleTheme.blue.bodyGradient)
}

#Preview("Motion Presets") {
    VStack(spacing: 28) {
        HStack(spacing: 20) {
            PlayPauseButton(isPlaying: false, action: {}, theme: .silver, motionPreset: .tight, scale: 0.8)
            PlayPauseButton(isPlaying: true, action: {}, theme: .silver, motionPreset: .tight, scale: 0.8)
        }
        Text("Tight")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack(spacing: 20) {
            PlayPauseButton(isPlaying: false, action: {}, theme: .silver, motionPreset: .soft, scale: 0.8)
            PlayPauseButton(isPlaying: true, action: {}, theme: .silver, motionPreset: .soft, scale: 0.8)
        }
        Text("Soft")
            .font(.caption)
            .foregroundStyle(.secondary)

        HStack(spacing: 20) {
            PlayPauseButton(isPlaying: false, action: {}, theme: .silver, motionPreset: .mechanical, scale: 0.8)
            PlayPauseButton(isPlaying: true, action: {}, theme: .silver, motionPreset: .mechanical, scale: 0.8)
        }
        Text("Mechanical")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding()
    .background(ShuffleTheme.silver.bodyGradient)
}
