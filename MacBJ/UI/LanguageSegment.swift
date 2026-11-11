import SwiftUI

/// 语言三选一。高光胶囊跟选中项走，窄的时候可以横向滚动，两端淡出。
struct LanguageSegment: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var frames: [LanguageChoice: CGRect] = [:]
    @State private var ready = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollSpan: CGFloat = 0

    private var choice: LanguageChoice { LanguageStore.shared.choice }

    var body: some View {
        let _ = LanguageStore.shared.choice
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                if let frame = frames[choice] {
                    Capsule()
                        .fill(palette.surface)
                        .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                        .shadow(color: .black.opacity(0.06), radius: 0.5, y: 0)
                        .frame(width: frame.width, height: 32)
                        .offset(x: frame.minX)
                        .animation(pillAnimation, value: choice)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 0) {
                    ForEach(LanguageChoice.allCases) { item in
                        segment(item)
                    }
                }
                .coordinateSpace(name: "language-segments")
            }
            .padding(3)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .onScrollGeometryChange(for: ScrollSample.self) { geo in
            ScrollSample(
                offset: geo.contentOffset.x + geo.contentInsets.leading,
                span: geo.contentSize.width - geo.containerSize.width
            )
        } action: { _, sample in
            scrollOffset = sample.offset
            scrollSpan = sample.span
        }
        .mask { edgeMask }
        .background(palette.field, in: Capsule())
        .overlay {
            Capsule()
                .stroke(focused ? palette.accentInk : Color.clear, lineWidth: 2)
        }
        .fixedSize(horizontal: true, vertical: true)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.home) { choose(LanguageChoice.allCases[0], focus: true) }
        .onKeyPress(.end) { choose(LanguageChoice.allCases[LanguageChoice.allCases.count - 1], focus: true) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("语言"))
        .task { ready = true }
    }

    private var pillAnimation: Animation? {
        reduceMotion || !ready ? nil : Motion.focus
    }

    private var edgeMask: some View {
        HStack(spacing: 0) {
            if scrollOffset > 1 {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
            Rectangle().fill(.black)
            if scrollSpan - scrollOffset > 1 {
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 16)
            }
        }
    }

    private func segment(_ item: LanguageChoice) -> some View {
        let selected = choice == item
        return Button {
            choose(item, focus: false)
        } label: {
            Text(item.segmentTitle)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: SegmentFrameKey.self,
                            value: [item: geo.frame(in: .named("language-segments"))]
                        )
                    }
                }
        }
        .buttonStyle(SegmentPressStyle())
        .accessibilityLabel(item.segmentTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onPreferenceChange(SegmentFrameKey.self) { frames.merge($0) { _, new in new } }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let items = LanguageChoice.allCases
        guard let index = items.firstIndex(of: choice) else { return .ignored }
        let next = (index + step + items.count) % items.count
        return choose(items[next], focus: true)
    }

    @discardableResult
    private func choose(_ item: LanguageChoice, focus: Bool) -> KeyPress.Result {
        LanguageStore.shared.choice = item
        if focus { focused = true }
        return .handled
    }
}

private struct ScrollSample: Equatable {
    var offset: CGFloat
    var span: CGFloat
}

private struct SegmentFrameKey: PreferenceKey {
    nonisolated(unsafe) static let defaultValue: [LanguageChoice: CGRect] = [:]
    static func reduce(value: inout [LanguageChoice: CGRect], nextValue: () -> [LanguageChoice: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct SegmentPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}
