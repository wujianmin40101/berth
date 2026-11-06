import SwiftUI

struct SunMoonMorphIcon: View {
    var isDark: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat
    @State private var velocity: CGFloat = 0
    @State private var target: CGFloat
    @State private var settled: Bool
    @State private var lastTick: Date?

    init(isDark: Bool, color: Color) {
        self.isDark = isDark
        self.color = color
        let initial: CGFloat = isDark ? 1 : 0
        _progress = State(initialValue: initial)
        _target = State(initialValue: initial)
        _settled = State(initialValue: true)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 120, paused: settled)) { timeline in
            Canvas { context, size in
                let path = Path(SunMoonPlan.shared.path(at: progress, in: size))
                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: max(1.25, size.width * 2 / 24), lineCap: .round, lineJoin: .round)
                )
            }
            .onChange(of: timeline.date) { _, date in
                advance(to: date)
            }
        }
        .onChange(of: isDark) { _, dark in
            aim(dark: dark)
        }
        .accessibilityHidden(true)
    }

    private func aim(dark: Bool) {
        target = dark ? 1 : 0
        guard !reduceMotion else {
            progress = target
            velocity = 0
            settled = true
            lastTick = nil
            return
        }
        velocity = min(14, max(-14, velocity))
        lastTick = nil
        settled = false
    }

    private func advance(to date: Date) {
        guard !settled else { return }
        let dt = min(0.05, lastTick.map { CGFloat(date.timeIntervalSince($0)) } ?? 1 / 60)
        lastTick = date
        guard dt > 0 else { return }
        let steps = max(1, min(16, Int(ceil(dt / (1 / 240)))))
        let slice = dt / CGFloat(steps)
        for _ in 0..<steps {
            let acceleration = 420 * (target - progress) - 30 * velocity
            velocity += acceleration * slice
            progress += velocity * slice
        }
        if abs(target - progress) < 0.001, abs(velocity) < 0.02 {
            progress = target
            velocity = 0
            settled = true
            lastTick = nil
        }
    }
}
