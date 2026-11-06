import SwiftUI

/// A soft band that travels from the top-left toward the bottom-right.
struct DiagonalSweep: View {
    var active: Bool
    @State private var progress: CGFloat = 0

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
        }
        .allowsHitTesting(false)
        .onAppear { play() }
        .onChange(of: active) { _, _ in play() }
    }

    private func play() {
        guard active else {
            progress = 0
            return
        }
        progress = 0
        withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
            progress = 1
        }
    }
}
