import SwiftUI

extension View {
    /// Pops a tile once each time `trigger` changes, after `delay`; a nil delay sits that beat out.
    /// With Reduce Motion it flashes the accent instead.
    public func tilePulse(trigger: Int, delay: Double?) -> some View {
        modifier(TilePulse(trigger: trigger, delay: delay))
    }

    /// Flashes an empty slot's outline each time `trigger` changes, for a batch that didn't fit.
    public func slotWarning(trigger: Int) -> some View {
        modifier(SlotWarning(trigger: trigger))
    }
}

private struct TilePulse: ViewModifier {
    let trigger: Int
    let delay: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let delay = self.delay ?? 0
        let peak = self.delay == nil ? 0.0 : 1.0
        if reduceMotion {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { tile, glow in
                tile.overlay {
                    RoundedRectangle(cornerRadius: CornerRadius.tile).fill(.accentText.opacity(glow))
                }
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: max(delay, 0.001))
                    LinearKeyframe(0.6 * peak, duration: 0.12)
                    LinearKeyframe(0, duration: 0.4)
                }
            }
        } else {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { tile, scale in
                tile.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    // A zero-length keyframe leaves the scale invalid and the tile undrawn.
                    LinearKeyframe(1, duration: max(delay, 0.001))
                    SpringKeyframe(1 + 0.28 * peak, duration: 0.12)
                    SpringKeyframe(1, duration: 0.3, spring: .bouncy)
                }
            }
        }
    }
}

private struct SlotWarning: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { slot, strength in
            slot.overlay {
                RoundedRectangle(cornerRadius: CornerRadius.tile)
                    .fill(.warning.opacity(strength * 0.35))
                    .strokeBorder(.warning.opacity(strength), lineWidth: 1.5)
            }
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1, duration: 0.1)
                LinearKeyframe(0.3, duration: 0.25)
                LinearKeyframe(1, duration: 0.25)
                LinearKeyframe(0.3, duration: 0.25)
                LinearKeyframe(1, duration: 0.25)
                LinearKeyframe(1, duration: 1)
                LinearKeyframe(0, duration: 0.4)
            }
        }
    }
}
