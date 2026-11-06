import AppKit
import SwiftUI

final class ThemeHost {
    weak var button: NSView?
    var curtain: ThemeCurtainView?
}

struct ThemeSwitchButton: View {
    var isDark: Bool
    var host: ThemeHost
    var action: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            SunMoonMorphIcon(isDark: isDark, color: palette.ink)
                .frame(width: 20, height: 20)
                .scaleEffect(isDark ? 1.08 : 1)
                .animation(reduceMotion ? .linear(duration: 0.01) : .timingCurve(0.18, 0.89, 0.32, 1.28, duration: 0.36), value: isDark)
        }
        .buttonStyle(ThemePressStyle())
        .frame(width: 38, height: 38)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(palette.line)
        )
        .background(ThemeAnchor(host: host))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .help(isDark ? "浅色模式" : "深色模式")
        .accessibilityLabel(isDark ? "切换到浅色模式" : "切换到深色模式")
        .accessibilityValue(isDark ? "深色" : "浅色")
    }
}

private struct ThemePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .animation(
                reduceMotion ? nil : .timingCurve(0.18, 0.89, 0.32, 1.28, duration: 0.15),
                value: configuration.isPressed
            )
    }
}

private struct ThemeAnchor: NSViewRepresentable {
    var host: ThemeHost

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        host.button = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        host.button = nsView
    }
}

final class ThemeCurtainView: NSView {
    private let imageLayer = CALayer()
    private let shapeMask = CAShapeLayer()
    private var center: CGPoint = .zero
    private var endRadius: CGFloat = 0
    private var expanding = true
    var onFinish: (() -> Void)?

    func prepare(image: CGImage, center: CGPoint, endRadius: CGFloat, expanding: Bool) {
        wantsLayer = true
        layer?.masksToBounds = true
        self.center = center
        self.endRadius = endRadius
        self.expanding = expanding

        imageLayer.frame = bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        shapeMask.frame = bounds
        shapeMask.fillColor = NSColor.black.cgColor
        shapeMask.fillRule = expanding ? .evenOdd : .nonZero

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.path = circlePath(radius: expanding ? 0 : endRadius)
        layer?.addSublayer(imageLayer)
        imageLayer.mask = shapeMask
        CATransaction.commit()
    }

    private var started: CFTimeInterval = 0

    func play() {
        started = CACurrentMediaTime()
        tick()
    }

    private func tick() {
        guard window != nil else { return }
        let raw = min(1, max(0, CGFloat(CACurrentMediaTime() - started) / 0.48))
        let eased = ThemeEase.reveal(raw)
        let radius = expanding ? eased * endRadius : (1 - eased) * endRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.path = circlePath(radius: radius)
        CATransaction.commit()
        guard raw < 1 else {
            removeFromSuperview()
            onFinish?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            self?.tick()
        }
    }

    private func circlePath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        if expanding {
            path.addRect(bounds)
        }
        let safe = max(0, radius)
        path.addEllipse(in: CGRect(x: center.x - safe, y: center.y - safe, width: safe * 2, height: safe * 2))
        return path
    }
}

enum ThemeEase {
    /// cubic-bezier(0.16, 1, 0.3, 1)
    static func reveal(_ time: CGFloat) -> CGFloat {
        let t = solve(time, x1: 0.16, x2: 0.3)
        return cubic(t, c1: 1, c2: 1)
    }

    private static func cubic(_ t: CGFloat, c1: CGFloat, c2: CGFloat) -> CGFloat {
        let u = 1 - t
        return 3 * u * u * t * c1 + 3 * u * t * t * c2 + t * t * t
    }

    private static func solve(_ x: CGFloat, x1: CGFloat, x2: CGFloat) -> CGFloat {
        var lo: CGFloat = 0
        var hi: CGFloat = 1
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            if cubic(mid, c1: x1, c2: x2) < x { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

enum ThemeCapture {
    static func cgImage(of view: NSView) -> CGImage? {
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 2, bounds.height > 2 else { return nil }
        let scale = view.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelsWide = max(1, Int((bounds.width * scale).rounded()))
        let pixelsHigh = max(1, Int((bounds.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = graphics
        view.wantsLayer = true
        guard let layer = view.layer else { return nil }
        layer.render(in: graphics.cgContext)
        return rep.cgImage
    }
}
