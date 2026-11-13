import SwiftUI

/// 手机任务页里的同级分页。高光胶囊跟手滑动，内容区另做沉降置换。
enum PhonePage: String, CaseIterable, Identifiable, Hashable {
    case schedule
    case navigate
    case read
    case gesture
    case typing
    case batch
    case list
    case recover
    case screen
    case reconnect

    var id: String { rawValue }

    var label: String {
        switch self {
        case .schedule: L("定时")
        case .navigate: L("导航")
        case .read: L("读取")
        case .gesture: L("手势")
        case .typing: L("输入")
        case .batch: L("连续")
        case .list: L("列表")
        case .recover: L("恢复")
        case .screen: L("画面")
        case .reconnect: L("连接")
        }
    }

    var heading: String {
        switch self {
        case .schedule: L("定时")
        case .navigate: L("App 导航与操作")
        case .read: L("页面读取")
        case .gesture: L("点击与手势")
        case .typing: L("中文与长文本输入")
        case .batch: L("连续任务")
        case .list: L("列表搜索与采集")
        case .recover: L("可见失败恢复")
        case .screen: L("实时手机屏幕")
        case .reconnect: L("连接恢复")
        }
    }

    var detail: String {
        switch self {
        case .schedule:
            L("查看已有打卡定时、执行日志，并增加新的定时。")
        case .navigate:
            L("打开目标 App，进入搜索、详情、设置或草稿页面。")
        case .read:
            L("获取紧凑控件树、文字、位置和实际截图。")
        case .gesture:
            L("按控件或坐标点击，滑动和拖动，等待页面目标出现。")
        case .typing:
            L("一次提供完整 Unicode 文字，长文本分段输入并支持续传。")
        case .batch:
            L("将已知点击、输入、等待等步骤组成一次 batch，减少模型往返。")
        case .list:
            L("有界滚动查找、重叠读取与去重，返回覆盖边界。")
        case .recover:
            L("控件被遮挡、未聚焦或树不完整时，查看新截图并重新选择点击位置。")
        case .screen:
            L("iPhone 外壳、设备状态、操作光效与清楚可见的点击 / 拖动提示。")
        case .reconnect:
            L("复用后台启动工作、重建失效会话；用户可点击刷新重新连接预览。")
        }
    }

    var tools: String {
        switch self {
        case .schedule:
            L("定时由本页写入 LaunchAgents，到点运行 iPhone Use 的打卡脚本。")
        case .navigate:
            L("对应 pua_apps、pua_launch_app。")
        case .read:
            L("对应 pua_observe、pua_find、pua_screenshot。")
        case .gesture:
            L("对应 pua_tap、pua_swipe、pua_press_button、pua_wait。")
        case .typing:
            L("对应 pua_type_text。")
        case .batch:
            L("对应 pua_batch。")
        case .list:
            L("对应 pua_scroll_find、pua_collect_list。")
        case .recover:
            L("定位失败时先看新截图，再用坐标点击，不盲目重放上一次操作。")
        case .screen:
            L("对应 pua_screen。画面只在预览时采集，不落盘。")
        case .reconnect:
            L("对应 pua_setup、pua_ready。刷新会重新读取连接，不重复启动已在跑的任务。")
        }
    }
}

private enum PhoneTabMotion {
    static let pill = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)
    static let hover = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}

private struct PhoneTabFrameKey: PreferenceKey {
    static let defaultValue: [PhonePage: CGRect] = [:]
    static func reduce(value: inout [PhonePage: CGRect], nextValue: () -> [PhonePage: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct PhoneTabStrip: View {
    var selection: PhonePage
    var reduceMotion: Bool
    var choose: (PhonePage) -> Void
    @Environment(\.palette) private var palette
    @State private var frames: [PhonePage: CGRect] = [:]
    @State private var pillReady = false
    @State private var hovered: PhonePage?
    @FocusState private var focused: PhonePage?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                strip
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, page in
                if reduceMotion {
                    proxy.scrollTo(page, anchor: .center)
                } else {
                    withAnimation(PhoneTabMotion.pill) {
                        proxy.scrollTo(page, anchor: .center)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("手机能力"))
    }

    private var strip: some View {
        ZStack(alignment: .topLeading) {
            if let frame = frames[selection] {
                Capsule(style: .continuous)
                    .fill(palette.surface)
                    .overlay(Capsule(style: .continuous).stroke(palette.line))
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.identity)
                    .animation(pillReady && !reduceMotion ? PhoneTabMotion.pill : nil, value: selection)
            }
            HStack(spacing: 0) {
                ForEach(PhonePage.allCases) { page in
                    tabButton(page)
                }
            }
        }
        .coordinateSpace(name: "phoneTabs")
        .onPreferenceChange(PhoneTabFrameKey.self) { frames in
            self.frames = frames
            if !pillReady, frames[selection] != nil {
                pillReady = true
            }
        }
        .padding(4)
        .background(palette.field, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(palette.line))
    }

    private func tabButton(_ page: PhonePage) -> some View {
        let selected = selection == page
        let hot = selected || hovered == page
        return Button {
            choose(page)
        } label: {
            Text(page.label)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(hot ? palette.ink : palette.textSecondary)
                .padding(.horizontal, 16)
                .frame(minWidth: 88, minHeight: 32)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PhoneTabFrameKey.self,
                    value: [page: geo.frame(in: .named("phoneTabs"))]
                )
            }
        }
        .id(page)
        .focused($focused, equals: page)
        .onHover { inside in
            hovered = inside ? page : (hovered == page ? nil : hovered)
        }
        .animation(reduceMotion ? nil : PhoneTabMotion.hover, value: hot)
        .onKeyPress(.leftArrow) {
            step(from: page, by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(from: page, by: 1)
            return .handled
        }
        .accessibilityLabel(page.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? L("已选") : L("未选"))
    }

    private func step(from page: PhonePage, by delta: Int) {
        let pages = PhonePage.allCases
        guard let index = pages.firstIndex(of: page) else { return }
        let next = pages[(index + delta + pages.count) % pages.count]
        focused = next
        choose(next)
    }
}
