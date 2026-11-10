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

    var body: some View {
        Button(action: action) {
            SunMoonMorphIcon(isDark: isDark, color: palette.ink)
                .frame(width: 20, height: 20)
                .frame(width: 38, height: 38)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(palette.line)
                )
        }
        .buttonStyle(ThemePressStyle())
        .frame(width: 44, height: 44)
        .background(ThemeAnchor(host: host))
        .contentShape(Rectangle())
        .help(isDark ? L("浅色模式") : L("深色模式"))
        .accessibilityLabel(isDark ? L("切换到浅色模式") : L("切换到深色模式"))
        .accessibilityValue(isDark ? L("深色") : L("浅色"))
    }
}

private struct ThemePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
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

    func play() {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = circlePath(radius: expanding ? 0 : endRadius)
        animation.toValue = circlePath(radius: expanding ? endRadius : 0)
        animation.duration = Motion.theme
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        shapeMask.add(animation, forKey: "reveal")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Motion.theme))
            guard window != nil else { return }
            removeFromSuperview()
            onFinish?()
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
