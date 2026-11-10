import SwiftUI

/// A soft band that travels from the top-left toward the bottom-right.
struct DiagonalSweep: View {
    var active: Bool
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var playing: Bool { active && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.white.opacity(0),
                    Color.white.opacity(0.42),
                    Color.white.opacity(0),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: max(80, geo.size.width * 0.38))
            .offset(
                x: -geo.size.width * 0.45 + progress * geo.size.width * 1.7,
                y: -geo.size.height * 0.2 + progress * geo.size.height * 0.45
            )
            .animation(playing ? Motion.sweep : nil, value: progress)
        }
        .allowsHitTesting(false)
        .onAppear { sync(playing) }
        .onChange(of: playing) { _, next in sync(next) }
    }

    private func sync(_ play: Bool) {
        if play {
            progress = 0
            Task { @MainActor in
                guard playing else { return }
                progress = 1
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { progress = 0 }
        }
    }
}
