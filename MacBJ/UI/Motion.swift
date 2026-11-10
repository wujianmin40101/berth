import SwiftUI

/// Locked motion tokens. Durations and curves come from the motion spec only.
enum Motion {
    /// 150ms, cubic-bezier(0.22, 1, 0.36, 1). No overshoot.
    static let press = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.15)

    /// 200ms easeOut. Color and hover only, never scale.
    static let color = Animation.easeOut(duration: 0.2)

    /// 240ms, cubic-bezier(0.16, 1, 0.3, 1). Overlay and hint enter.
    static let enter = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.24)

    /// 160ms press ease. Overlay and hint exit.
    static let exit = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)

    /// 300ms standard ease. Page enter.
    static let pageIn = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.3)

    /// 150ms, cubic-bezier(0, 0, 0.58, 1). Page leave.
    static let pageOut = Animation.timingCurve(0, 0, 0.58, 1, duration: 0.15)

    /// Reduce Motion page fade. No offset.
    static let reduced = Animation.linear(duration: 0.08)

    /// 240ms standard ease. Language slider and disk treemap focus.
    static let focus = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.24)

    /// 1.5s linear sweep. Play only while loading.
    static let sweep = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

    /// 0.9s easeInOut skeleton pulse.
    static let skeleton = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)

    /// Full-screen theme curtain only.
    static let theme: TimeInterval = 0.48
}
