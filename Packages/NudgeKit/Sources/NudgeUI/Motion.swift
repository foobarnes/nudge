import SwiftUI

// Every animation plays once per event and collapses to a crossfade (or nothing) under Reduce Motion.

enum Motion {
    static let morph = Animation.spring(duration: 0.35, bounce: 0.18)
    static let bounce = Animation.spring(duration: 0.35, bounce: 0.45)
    static let tint = Animation.easeInOut(duration: 0.5)
    static let dim = Animation.easeInOut(duration: 0.4)
    static let chip = Animation.spring(duration: 0.4, bounce: 0.2)
    static let rowSlide = Animation.easeInOut(duration: 0.3)
    static let roll = Animation.spring(duration: 0.3, bounce: 0.1)
    static let crossfade = Animation.easeInOut(duration: 0.25)
    static let shrink = Animation.easeIn(duration: 0.4)

    static func pick(_ animation: Animation, reduced: Bool) -> Animation? {
        reduced ? crossfade : animation
    }
}

extension View {
    /// Applies `animation` to changes of `value`, or a plain crossfade when Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.pick(animation, reduced: reduceMotion), value: value)
    }
}
