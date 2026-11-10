import SwiftUI

struct RuntimeKindBar: View {
    var model: AppModel
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tabFrames: [RuntimeKind: CGRect] = [:]
    @State private var pillMoves = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(RuntimeKind.allCases) { item in
                    Button(item.title) {
                        model.selectedKind = item
                    }
                    .buttonStyle(RuntimePickStyle(selected: model.selectedKind == item))
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RuntimeTabFrames.self,
                                value: [item: proxy.frame(in: .named("runtimeTabs"))]
                            )
                        }
                    }
                    .accessibilityAddTraits(model.selectedKind == item ? .isSelected : [])
                    .onKeyPress(.leftArrow) {
                        stepKind(-1)
                        return .handled
                    }
                    .onKeyPress(.rightArrow) {
                        stepKind(1)
                        return .handled
                    }
                }
            }
            .padding(3)
            .coordinateSpace(name: "runtimeTabs")
            .onPreferenceChange(RuntimeTabFrames.self) { frames in
                guard !tabFrames.matches(frames) else { return }
                tabFrames = frames
            }
            .background(alignment: .topLeading) {
                if let rect = tabFrames[model.selectedKind], rect.width > 1 {
                    Capsule()
                        .fill(palette.surface)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                        .animation(
                            pillMoves && !reduceMotion ? Motion.focus : nil,
                            value: model.selectedKind
                        )
                }
            }
            .background(palette.field, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("运行时"))

            if let selected = model.snapshots[model.selectedKind] {
                Text(selected.backend.title)
                    .font(.system(size: 12, weight: .medium))
                    .textSecondaryStyle()
            }
            Button {
                model.refresh(model.selectedKind)
            } label: {
                Label(L("更新数据"), systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(TintCapsuleStyle())
            .disabled(model.loading.contains(model.selectedKind))
            Spacer(minLength: 0)
        }
        .onAppear {
            DispatchQueue.main.async { pillMoves = true }
        }
    }

    private func stepKind(_ delta: Int) {
        let kinds = Array(RuntimeKind.allCases)
        guard let index = kinds.firstIndex(of: model.selectedKind) else { return }
        let next = (index + delta + kinds.count) % kinds.count
        model.selectedKind = kinds[next]
    }
}

private struct RuntimeTabFrames: PreferenceKey {
    static var defaultValue: [RuntimeKind: CGRect] = [:]

    static func reduce(
        value: inout [RuntimeKind: CGRect],
        nextValue: () -> [RuntimeKind: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension Dictionary where Key == RuntimeKind, Value == CGRect {
    func matches(_ other: [RuntimeKind: CGRect]) -> Bool {
        guard count == other.count else { return false }
        for (key, rect) in self {
            guard let next = other[key],
                  abs(rect.minX - next.minX) < 0.5,
                  abs(rect.minY - next.minY) < 0.5,
                  abs(rect.width - next.width) < 0.5,
                  abs(rect.height - next.height) < 0.5 else {
                return false
            }
        }
        return true
    }
}

private struct RuntimePickStyle: ButtonStyle {
    var selected: Bool
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
            .pressFeedback(pressed: configuration.isPressed)
    }
}
