import AppKit
import SwiftUI

enum WorkspacePage: Hashable, Identifiable {
    case versions
    case projects
    case toolbox
    case settings
    case tool(ToolboxPlugin)

    var id: String {
        switch self {
        case .versions: "versions"
        case .projects: "projects"
        case .toolbox: "toolbox"
        case .settings: "settings"
        case .tool(let plugin): "tool-\(plugin.rawValue)"
        }
    }

    var title: String {
        switch self {
        case .versions: L("版本")
        case .projects: L("项目")
        case .toolbox: L("工具")
        case .settings: L("设置")
        case .tool(let plugin): plugin.title
        }
    }

    var icon: String {
        switch self {
        case .versions: "square.stack.3d.up"
        case .projects: "folder"
        case .toolbox: "wrench.and.screwdriver"
        case .settings: "gearshape"
        case .tool(let plugin): plugin.icon
        }
    }
}

struct WorkspacePalette {
    var scheme: ColorScheme

    /// #F8F7FB / #17171C. Window and sidebar ground.
    var canvas: Color {
        scheme == .dark
            ? Color(red: 23.0 / 255, green: 23.0 / 255, blue: 28.0 / 255)
            : Color(red: 248.0 / 255, green: 247.0 / 255, blue: 251.0 / 255)
    }

    /// #FFFFFF / #242429. Panels, tables, theme button ground.
    var surface: Color {
        scheme == .dark
            ? Color(red: 36.0 / 255, green: 36.0 / 255, blue: 41.0 / 255)
            : .white
    }

    /// #17171F / #FFFFFF. Titles, body, default icons.
    var ink: Color {
        scheme == .dark ? .white : Color(red: 23.0 / 255, green: 23.0 / 255, blue: 31.0 / 255)
    }

    /// #5F6368 / #A2A2A4. Subtitles, descriptions, empty states.
    var textSecondary: Color {
        scheme == .dark
            ? Color(red: 162.0 / 255, green: 162.0 / 255, blue: 164.0 / 255)
            : Color(red: 95.0 / 255, green: 99.0 / 255, blue: 104.0 / 255)
    }

    /// #7458F6. Fills only. Not for body or link text.
    var accentFill: Color { Color(red: 116.0 / 255, green: 88.0 / 255, blue: 246.0 / 255) }

    /// #6246F0 / #8B78F8. Selected text, links, badge and capsule labels.
    var accentInk: Color {
        scheme == .dark
            ? Color(red: 139.0 / 255, green: 120.0 / 255, blue: 248.0 / 255)
            : Color(red: 98.0 / 255, green: 70.0 / 255, blue: 240.0 / 255)
    }

    /// Light: accentFill at 14% on the current background. Dark: solid #24203B.
    var accentSoft: Color {
        scheme == .dark
            ? Color(red: 36.0 / 255, green: 32.0 / 255, blue: 59.0 / 255)
            : accentFill.opacity(0.14)
    }

    /// Black 4.5% / white 6%. Fields, menu buttons, table header.
    var field: Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }

    /// Black 6% / white 8%. Strokes and dividers.
    var line: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    /// Black 6% / white 8%. Sidebar row hover.
    var hoverFill: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    /// #CED3D6 / #3B454A. Disk treemap tracks only.
    var chartTrack: Color {
        scheme == .dark
            ? Color(red: 59.0 / 255, green: 69.0 / 255, blue: 74.0 / 255)
            : Color(red: 206.0 / 255, green: 211.0 / 255, blue: 214.0 / 255)
    }

    /// #21292C, or ink in dark. Treemap labels only.
    var chartInk: Color {
        scheme == .dark ? ink : Color(red: 33.0 / 255, green: 41.0 / 255, blue: 44.0 / 255)
    }
}

private struct WorkspacePaletteKey: EnvironmentKey {
    static let defaultValue = WorkspacePalette(scheme: .light)
}

extension EnvironmentValues {
    var palette: WorkspacePalette {
        get { self[WorkspacePaletteKey.self] }
        set { self[WorkspacePaletteKey.self] = newValue }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

struct WorkspaceBreadcrumb: View {
    var page: WorkspacePage
    var palette: WorkspacePalette

    var body: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(L("工作区"))
                .foregroundStyle(palette.ink)
            Text("/")
                .foregroundStyle(palette.textSecondary)
            Text(page.title)
                .foregroundStyle(palette.textSecondary)
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WindowDragArea())
    }
}

enum RailMetrics {
    static let icon: CGFloat = 40
    /// 收起时图标左右留出的空隙。最小宽度就是图标加上这两边。
    static let side: CGFloat = 18
    static let collapsed: CGFloat = icon + side * 2
    static let expanded: CGFloat = 220
    static let handle: CGFloat = 12
    private static let labelSpan: CGFloat = 64
    private static let key = "macbj.rail.width"

    static var saved: CGFloat {
        let raw = UserDefaults.standard.double(forKey: key)
        guard raw > 0 else { return collapsed }
        if raw < collapsed { return collapsed }
        return clamped(raw)
    }

    static func save(_ width: CGFloat) {
        UserDefaults.standard.set(clamped(width), forKey: key)
    }

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(expanded, max(collapsed, width))
    }

    /// 越过最小或最大宽度时，只跟手 0.55，并限制在 28pt 以内。
    static func rubber(_ proposed: CGFloat) -> CGFloat {
        if proposed < collapsed {
            return collapsed - min(28, (collapsed - proposed) * 0.55)
        }
        if proposed > expanded {
            return expanded + min(28, (proposed - expanded) * 0.55)
        }
        return proposed
    }

    static func labelProgress(_ width: CGFloat) -> CGFloat {
        min(1, max(0, (width - collapsed) / labelSpan))
    }
}

struct WorkspaceRail: View {
    @Binding var page: WorkspacePage
    var width: CGFloat
    var tools: [ToolboxPlugin]
    var isDark: Bool
    var host: ThemeHost
    var toggleTheme: () -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredID: String?
    @State private var hintDismissed = false
    @FocusState private var focusedID: String?

    private var labelProgress: CGFloat { RailMetrics.labelProgress(width) }
    /// 只有收到最窄、名称已经藏起来时，才在右侧补提示。
    private var hintsOnHover: Bool { width <= RailMetrics.collapsed + 0.5 }
    private var hintEnter: Animation { Motion.enter }
    private var hintExit: Animation { Motion.exit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledRow(title: ProductName.title, prominent: true, hovered: hoveredID == "brand") {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: RailMetrics.icon, height: RailMetrics.icon)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .contentShape(Rectangle())
            .onHover { trackHover("brand", inside: $0) }
            .overlay(alignment: .leading) {
                railHint(id: "brand", title: ProductName.title, symbol: nil)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ProductName.title)
            .padding(.bottom, 10)

            railButton(.versions)
            railButton(.projects)
            railButton(.toolbox)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(tools) { plugin in
                        toolButton(plugin)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: labelProgress == 0 ? 0 : 8) {
                ThemeSwitchButton(isDark: isDark, host: host, action: toggleTheme)
                if labelProgress > 0 {
                    Button(action: toggleTheme) {
                        Text(isDark ? L("深色模式") : L("浅色模式"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .opacity(labelProgress)
                            .offset(x: (1 - labelProgress) * -8)
                    }
                    .buttonStyle(PlainPressStyle())
                    .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, RailMetrics.side)
            .frame(width: width, alignment: .leading)
            .background { hoverPlate(hoveredID == "theme") }
            .contentShape(Rectangle())
            .onHover { trackHover("theme", inside: $0) }
            .overlay(alignment: .leading) {
                railHint(id: "theme", title: isDark ? L("深色模式") : L("浅色模式"), symbol: "circle.lefthalf.filled")
            }
            railButton(.settings)
        }
        .padding(.vertical, 8)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .onKeyPress(.escape) {
            hintDismissed = true
            return .handled
        }
    }

    private func railButton(_ item: WorkspacePage) -> some View {
        iconButton(title: item.title, icon: item.icon, selected: page == item) {
            page = item
        }
    }

    private func toolButton(_ plugin: ToolboxPlugin) -> some View {
        let selected: Bool = {
            if case .tool(let current) = page { return current == plugin }
            return false
        }()
        return iconButton(title: plugin.title, icon: plugin.icon, selected: selected) {
            page = .tool(plugin)
        }
    }

    private func iconButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            labeledRow(title: title, selected: selected, hovered: hoveredID == title) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: RailMetrics.icon, height: RailMetrics.icon)
                    .background(selected ? palette.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(selected ? palette.accentInk : palette.textSecondary)
                    .animation(reduceMotion ? nil : Motion.color, value: selected)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainPressStyle())
        .contentShape(Rectangle())
        .focused($focusedID, equals: title)
        .onHover { trackHover(title, inside: $0) }
        .onKeyPress(.escape) {
            hintDismissed = true
            return .handled
        }
        .overlay(alignment: .leading) {
            railHint(id: title, title: title, symbol: icon)
        }
        .accessibilityLabel(title)
    }

    private func hintVisible(_ id: String) -> Bool {
        guard hintsOnHover, !hintDismissed else { return false }
        if let hoveredID { return hoveredID == id }
        return focusedID == id
    }

    private func trackHover(_ id: String, inside: Bool) {
        if inside {
            hintDismissed = false
            hoveredID = id
        } else if hoveredID == id {
            hoveredID = nil
        }
    }

    private func railHint(id: String, title: String, symbol: String?) -> some View {
        let visible = hintVisible(id)
        let reduce = reduceMotion
        return RailHoverChip(title: title, symbol: symbol)
            .padding(18)
            .fixedSize()
            .offset(x: width + RailMetrics.handle + 6 - 18)
            .opacity(visible ? 1 : 0)
            .offset(y: reduce || visible ? 0 : 8)
            .animation(reduce ? nil : (visible ? hintEnter : hintExit), value: visible)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func labeledRow<Icon: View>(
        title: String,
        selected: Bool = false,
        prominent: Bool = false,
        hovered: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: labelProgress == 0 ? 0 : 8) {
            icon()
            if labelProgress > 0 {
                Text(title)
                    .font(.system(size: prominent ? 18 : 13, weight: prominent || selected ? .semibold : .medium))
                    .foregroundStyle(prominent ? palette.ink : (selected ? palette.accentInk : palette.textSecondary))
                    .animation(reduceMotion ? nil : Motion.color, value: selected)
                    .lineLimit(1)
                    .opacity(labelProgress)
                    .offset(x: (1 - labelProgress) * -8)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RailMetrics.side)
        .frame(minHeight: 44)
        .frame(width: width, alignment: .leading)
        .background { hoverPlate(hovered) }
        .contentShape(Rectangle())
    }

    /// 深色底比导航栏窄一圈，左右留出空隙；整行仍然是触摸范围。
    private func hoverPlate(_ visible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(palette.hoverFill)
            .padding(.horizontal, 8)
            .opacity(visible ? 1 : 0)
            .animation(reduceMotion ? nil : Motion.color, value: visible)
    }
}

private struct RailHoverChip: View {
    var title: String
    var symbol: String?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
            } else {
                Image("BrandMark")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(chipFill)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(palette.scheme == .dark ? 0.45 : 0.16), radius: 14, y: 4)
        .shadow(color: .black.opacity(palette.scheme == .dark ? 0.28 : 0.08), radius: 2, y: 1)
    }

    private var chipFill: Color { palette.surface }
}

struct WorkspaceRailColumn: View {
    @Binding var page: WorkspacePage
    var tools: [ToolboxPlugin]
    var isDark: Bool
    var host: ThemeHost
    var toggleTheme: () -> Void
    @State private var width = RailMetrics.saved
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceRail(
                page: $page,
                width: width,
                tools: tools,
                isDark: isDark,
                host: host,
                toggleTheme: toggleTheme
            )
            .zIndex(1)
            RailResizeHandle(width: $width)
        }
        .background(palette.canvas)
        .contentShape(Rectangle())
        .frame(maxHeight: .infinity, alignment: .leading)
    }
}

struct RailResizeHandle: View {
    @Binding var width: CGFloat
    @Environment(\.palette) private var palette
    @State private var dragging = false
    @State private var hovered = false
    @State private var dragStart: CGFloat = RailMetrics.collapsed
    @FocusState private var focused: Bool

    private var active: Bool { dragging || hovered || focused }

    var body: some View {
        ZStack {
            HandleChrome(active: active, dragging: dragging)
        }
        .frame(width: RailMetrics.handle)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
        .gesture(drag)
        .onTapGesture(count: 2) { settle(RailMetrics.collapsed) }
        .onHover { hovered = $0 }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            let step: CGFloat = press.modifiers.contains(.shift) ? 64 : 16
            switch press.key {
            case .leftArrow:
                settle(width - step)
                return .handled
            case .rightArrow:
                settle(width + step)
                return .handled
            default:
                return .ignored
            }
        }
        .accessibilityLabel(L("导航宽度"))
        .accessibilityValue("\(Int(width.rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: settle(width + 16)
            case .decrement: settle(width - 16)
            @unknown default: break
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if !dragging {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragging = true
                        dragStart = width
                    }
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    width = RailMetrics.rubber(dragStart + value.translation.width).rounded()
                }
            }
            .onEnded { _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { dragging = false }
                settle(width)
            }
    }

    private func settle(_ proposed: CGFloat) {
        let target = RailMetrics.clamped(proposed)
        width = target
        RailMetrics.save(target)
    }
}

private struct HandleChrome: View {
    var active: Bool
    var dragging: Bool
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Rectangle()
                .fill(line)
                .frame(width: 1)
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(grip)
                        .frame(width: 3, height: 3)
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.color, value: active)
    }

    private var line: Color {
        if dragging { return palette.ink.opacity(0.22) }
        if active { return palette.ink.opacity(0.14) }
        return palette.ink.opacity(0.06)
    }

    private var grip: Color {
        if dragging { return palette.ink.opacity(0.34) }
        if active { return palette.ink.opacity(0.22) }
        return palette.ink.opacity(0.12)
    }
}

struct PageHeader: View {
    var title: String
    var subtitle: String
    var help: String? = nil
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var actionDisabled: Bool = false
    var action: (() -> Void)? = nil
    @Environment(\.palette) private var palette
    @Environment(\.presentFeatureHelp) private var presentFeatureHelp

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                    if let help, !help.isEmpty {
                        Button {
                            presentFeatureHelp?(title, help)
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainPressStyle(iconOnly: true))
                        .accessibilityLabel(L("%@的说明", title))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 16)
            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon ?? "arrow.triangle.2.circlepath")
                }
                .buttonStyle(TintCapsuleStyle())
                .disabled(actionDisabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct WorkspacePanel<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.line)
            )
    }
}

struct TintCapsuleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TintCapsuleBody(configuration: configuration)
    }
}

private struct TintCapsuleBody: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isEnabled ? palette.accentInk : palette.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background {
                Capsule().fill(isEnabled ? palette.accentSoft : palette.field)
                if isEnabled && hovered {
                    Capsule().fill(palette.ink.opacity(0.04))
                }
            }
            .contentShape(Capsule())
            .pressFeedback(pressed: configuration.isPressed, enabled: isEnabled)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : Motion.color, value: hovered)
            .animation(reduceMotion ? nil : Motion.color, value: isEnabled)
    }
}

struct FieldMenuStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FieldMenuBody(configuration: configuration)
    }
}

private struct FieldMenuBody: View {
    var configuration: ButtonStyleConfiguration
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? palette.ink : palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
            .pressFeedback(pressed: configuration.isPressed, enabled: isEnabled)
    }
}

/// 无边框按钮的按压。带字按钮缩到 0.97，纯图标缩到 0.96。
struct PlainPressStyle: ButtonStyle {
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        PlainPressBody(configuration: configuration, iconOnly: iconOnly)
    }
}

private struct PlainPressBody: View {
    var configuration: ButtonStyleConfiguration
    var iconOnly: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .pressFeedback(pressed: configuration.isPressed, iconOnly: iconOnly, enabled: isEnabled)
    }
}

struct PressFeedback: ViewModifier {
    var pressed: Bool
    var iconOnly = false
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var scale: CGFloat {
        guard enabled, !reduceMotion, pressed else { return 1 }
        return iconOnly ? 0.96 : 0.97
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(reduceMotion || !enabled ? nil : Motion.press, value: pressed)
    }
}

extension View {
    func pressFeedback(pressed: Bool, iconOnly: Bool = false, enabled: Bool = true) -> some View {
        modifier(PressFeedback(pressed: pressed, iconOnly: iconOnly, enabled: enabled))
    }

    func textSecondaryStyle() -> some View {
        modifier(TextSecondaryStyle())
    }
}

private struct TextSecondaryStyle: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content.foregroundStyle(palette.textSecondary)
    }
}

func catalogTitle(_ version: RuntimeVersion) -> String {
    if version.name == "system" { return L("系统") }
    if version.name.hasPrefix("v"), version.name.dropFirst().first?.isNumber == true {
        return version.name
    }
    return version.title
}
