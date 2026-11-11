import AppKit
import SwiftUI

/// 第一次打开才播放。播完或被跳过之后，下次冷启动直接进首页。
enum OpeningStore {
    static let playedKey = "macbj.opening.played"

    static var hasPlayed: Bool {
        UserDefaults.standard.bool(forKey: playedKey)
    }

    static func markPlayed() {
        UserDefaults.standard.set(true, forKey: playedKey)
    }
}

struct OpeningRevealState: Equatable {
    /// nil 表示各块已经在静止位置。负数表示都还没开始。
    var shownThrough: Int?
    var animate: Bool

    static let rest = OpeningRevealState(shownThrough: nil, animate: false)
}

private struct OpeningRevealKey: EnvironmentKey {
    static let defaultValue = OpeningRevealState.rest
}

extension EnvironmentValues {
    var openingReveal: OpeningRevealState {
        get { self[OpeningRevealKey.self] }
        set { self[OpeningRevealKey.self] = newValue }
    }
}

extension View {
    func openingBlock(_ index: Int) -> some View {
        modifier(OpeningBlockModifier(index: index))
    }
}

private struct OpeningBlockModifier: ViewModifier {
    var index: Int
    @Environment(\.openingReveal) private var reveal

    func body(content: Content) -> some View {
        let visible = reveal.shownThrough.map { index <= $0 } ?? true
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 8)
    }
}

enum WindowCanvas {
    static var systemScheme: ColorScheme? {
        let name = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if name == .darkAqua { return .dark }
        if name == .aqua { return .light }
        return nil
    }

    static func color(for scheme: ColorScheme) -> NSColor {
        if scheme == .dark {
            return NSColor(srgbRed: 23.0 / 255, green: 23.0 / 255, blue: 28.0 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 248.0 / 255, green: 247.0 / 255, blue: 251.0 / 255, alpha: 1)
    }
}

/// 窗口一挂上就涂画布色，避免进程起来时先闪一帧白。
struct WindowCanvasInstaller: NSViewRepresentable {
    var scheme: ColorScheme

    func makeNSView(context: Context) -> NSView {
        let view = WindowCanvasView()
        view.color = WindowCanvas.color(for: scheme)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowCanvasView else { return }
        view.color = WindowCanvas.color(for: scheme)
        view.apply()
    }
}

private final class WindowCanvasView: NSView {
    var color: NSColor = .windowBackgroundColor

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard let newWindow else { return }
        paint(newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func hitTest(_: NSPoint) -> NSView? { nil }

    func apply() {
        guard let window else { return }
        paint(window)
    }

    private func paint(_ window: NSWindow) {
        window.backgroundColor = color
        window.isOpaque = true
        if let frame = window.contentView?.superview {
            frame.wantsLayer = true
            frame.layer?.backgroundColor = color.cgColor
        }
    }
}

struct OpeningCurtain: View {
    var door: CGFloat
    var logoOpacity: Double
    var sealed: Bool
    var onSkip: () -> Void
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if sealed {
                palette.canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    panel(.left, size: size)
                    panel(.right, size: size)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSkip)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.command) { return .ignored }
            onSkip()
            return .handled
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("跳过开场"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onSkip)
    }

    private enum Side { case left, right }

    private func panel(_ side: Side, size: CGSize) -> some View {
        let finalScale = max(size.width, size.height) / 80
        let scale = 1 + (finalScale - 1) * door
        let travel = size.width / 2 + 40 * finalScale + 8
        let shift = door * travel
        let x: CGFloat = side == .left ? -shift : size.width / 2 + shift
        return palette.canvas
            .frame(width: max(0, size.width / 2), height: max(0, size.height))
            .overlay(alignment: side == .left ? .trailing : .leading) {
                logo(side)
                    .scaleEffect(scale)
                    .opacity(logoOpacity)
                    .offset(x: side == .left ? 40 : -40)
            }
            .offset(x: x)
    }

    private func logo(_ side: Side) -> some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.high)
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .mask(alignment: side == .left ? .leading : .trailing) {
                Rectangle().frame(width: 40, height: 80)
            }
            .accessibilityHidden(true)
    }
}

/// 开场时任何普通按键都跳过。命令键留给系统快捷键。
/// 监听回调不捕获界面，只发通知，避免在按键回调里拆掉监听。
final class OpeningKeyMonitor: @unchecked Sendable {
    static let skipNote = Notification.Name("berth.opening.skip")
    private let lock = NSLock()
    private var token: Any?

    func start() {
        stop()
        let next = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) { return event }
            if event.isARepeat { return nil }
            Task { @MainActor in
                NotificationCenter.default.post(name: OpeningKeyMonitor.skipNote, object: nil)
            }
            return nil
        }
        lock.lock()
        token = next
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let current = token
        token = nil
        lock.unlock()
        if let current {
            NSEvent.removeMonitor(current)
        }
    }

    deinit {
        if let token {
            NSEvent.removeMonitor(token)
        }
    }
}
