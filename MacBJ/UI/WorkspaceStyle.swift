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

    var canvas: Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.09, blue: 0.11)
            : Color(red: 0.973, green: 0.969, blue: 0.984)
    }

    var surface: Color {
        scheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.16) : .white
    }

    var ink: Color {
        scheme == .dark ? .white : Color(red: 0.09, green: 0.09, blue: 0.12)
    }

    var accent: Color { Color(red: 0.455, green: 0.345, blue: 0.965) }

    var accentSoft: Color { accent.opacity(scheme == .dark ? 0.32 : 0.14) }

    var card: Color {
        scheme == .dark
            ? Color(red: 0.18, green: 0.15, blue: 0.28)
            : Color(red: 0.941, green: 0.922, blue: 0.992)
    }

    var field: Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }

    var line: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
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
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(L("工作区"))
            Text("/")
                .foregroundStyle(.tertiary)
            Text(page.title)
                .foregroundStyle(.secondary)
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
    private var hintEnter: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.24) }
    private var hintExit: Animation { .timingCurve(0.22, 1, 0.36, 1, duration: 0.12) }
    private var hoverFill: Color {
        palette.scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

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
                    .frame(width: RailMetrics.icon, height: RailMetrics.icon)
                if labelProgress > 0 {
                    Button(action: toggleTheme) {
                        Text(isDark ? L("深色模式") : L("浅色模式"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(selected ? palette.accent : Color.secondary)
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
            .scaleEffect(reduce ? 1 : (visible ? 1 : 0.96))
            .offset(y: reduce ? 0 : (visible ? 0 : 4))
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
                    .foregroundStyle(prominent ? palette.ink : (selected ? palette.accent : Color.secondary))
                    .lineLimit(1)
                    .opacity(labelProgress)
                    .offset(x: (1 - labelProgress) * -8)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RailMetrics.side)
        .frame(width: width, alignment: .leading)
        .background { hoverPlate(hovered) }
        .contentShape(Rectangle())
    }

    /// 深色底比导航栏窄一圈，左右留出空隙；整行仍然是触摸范围。
    private func hoverPlate(_ visible: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(hoverFill)
            .padding(.horizontal, 8)
            .opacity(visible ? 1 : 0)
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

    private var chipFill: Color {
        palette.scheme == .dark
            ? Color(red: 0.23, green: 0.23, blue: 0.25)
            : Color(red: 0.925, green: 0.925, blue: 0.937)
    }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragging = false
    @State private var hovered = false
    @State private var dragStart: CGFloat = RailMetrics.collapsed
    @FocusState private var focused: Bool

    private var active: Bool { dragging || hovered || focused }
    private var spring: Animation { .timingCurve(0.16, 1, 0.3, 1, duration: 0.4) }

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
        if reduceMotion || abs(width - target) < 0.5 {
            width = target
        } else {
            withAnimation(spring) { width = target }
        }
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: active)
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
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainPressStyle(iconOnly: true))
                        .accessibilityLabel(L("%@的说明", title))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
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
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(palette.accentSoft, in: Capsule())
            .foregroundStyle(palette.accent)
            .pressFeedback(pressed: configuration.isPressed, primary: true)
    }
}

struct FieldMenuStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(palette.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(.primary)
            .pressFeedback(pressed: configuration.isPressed)
    }
}

/// 无边框按钮的按压。普通按钮缩到 0.97，纯图标缩到 0.96。
struct PlainPressStyle: ButtonStyle {
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .pressFeedback(pressed: configuration.isPressed, iconOnly: iconOnly)
    }
}

struct PressFeedback: ViewModifier {
    var pressed: Bool
    var iconOnly = false
    var primary = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(reduceMotion || !pressed ? 1 : (iconOnly ? 0.96 : 0.97))
            .animation(
                reduceMotion ? nil : .timingCurve(0.18, 0.89, 0.32, 1.28, duration: 0.15),
                value: pressed
            )
            .opacity(primary && pressed ? 0.84 : 1)
    }
}

extension View {
    func pressFeedback(pressed: Bool, iconOnly: Bool = false, primary: Bool = false) -> some View {
        modifier(PressFeedback(pressed: pressed, iconOnly: iconOnly, primary: primary))
    }
}

func catalogTitle(_ version: RuntimeVersion) -> String {
    if version.name == "system" { return L("系统") }
    if version.name.hasPrefix("v"), version.name.dropFirst().first?.isNumber == true {
        return version.name
    }
    return version.title
}
