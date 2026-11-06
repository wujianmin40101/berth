import AppKit
import SwiftUI

private enum MachineSection: String, CaseIterable, Identifiable {
    case memory
    case uninstall
    case caches
    case disk
    case speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: L("内存分布")
        case .uninstall: L("卸载应用")
        case .caches: L("清理缓存")
        case .disk: L("启动磁盘")
        case .speed: L("优化速度")
        }
    }

    var icon: String {
        switch self {
        case .memory: "chart.pie"
        case .uninstall: "trash"
        case .caches: "internaldrive"
        case .disk: "internaldrive.fill"
        case .speed: "hare"
        }
    }
}

struct MachineCareTool: View {
    @Environment(\.palette) private var palette
    @State private var section = MachineSection.memory

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(MachineSection.allCases) { item in
                    Button {
                        section = item
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.icon)
                                .frame(width: 16)
                            Text(item.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainPressStyle())
                    .background(section == item ? palette.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .frame(width: 168, alignment: .topLeading)
            Rectangle()
                .fill(palette.line)
                .frame(width: 1)
            Group {
                switch section {
                case .memory:
                    MemoryMapTool()
                case .uninstall:
                    AppUninstallTool()
                case .caches:
                    CacheCleanTool()
                case .disk:
                    DiskMapTool()
                case .speed:
                    SpeedTuneTool()
                }
            }
            .padding(.leading, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.leading, -28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DiskMapChart: View {
    var nodes: [DiskNode]
    var parentBytes: UInt64
    var onOpen: (DiskNode) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?
    @State private var pointer: CGPoint?

    private var cellFill: Color {
        palette.scheme == .dark
            ? Color(red: 0.23, green: 0.27, blue: 0.29)
            : Color(red: 206 / 255, green: 211 / 255, blue: 214 / 255)
    }

    private var labelFill: Color {
        palette.scheme == .dark
            ? Color.white.opacity(0.92)
            : Color(red: 33 / 255, green: 41 / 255, blue: 44 / 255)
    }

    var body: some View {
        GeometryReader { geo in
            let inputs = nodes.map { TreemapInput(id: $0.id, title: $0.name, value: Double($0.bytes)) }
            let tiles = TreemapLayout.tiles(inputs, in: CGRect(origin: .zero, size: geo.size))
            let lookup = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ZStack(alignment: .topLeading) {
                ForEach(tiles) { tile in
                    if let node = lookup[tile.id] {
                        block(node, frame: Self.split(tile.rect))
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard case .active(let point) = phase else {
                    hovered = nil
                    pointer = nil
                    return
                }
                pointer = point
                let next = tiles.first { Self.split($0.rect).contains(point) }?.id
                if hovered != next { hovered = next }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    guard let id = tiles.first(where: { Self.split($0.rect).contains(value.location) })?.id,
                          let node = lookup[id], node.canEnter else { return }
                    onOpen(node)
                }
            )
            .overlay {
                if let hovered, let node = lookup[hovered], let pointer {
                    tip(node, at: pointer, in: geo.size)
                        .allowsHitTesting(false)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        }
        .focusable()
        .onKeyPress(.return) {
            guard let hovered, let node = find(hovered, in: nodes), node.canEnter else { return .ignored }
            onOpen(node)
            return .handled
        }
        .pointerStyle(hovered.flatMap { find($0, in: nodes) }?.canEnter == true ? .link : .default)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("启动磁盘矩形树图"))
    }

    private func block(_ node: DiskNode, frame: CGRect) -> some View {
        let active = hovered == node.path
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(cellFill)
            if frame.width >= 36, frame.height >= 18 {
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.system(size: 12, weight: active ? .semibold : .medium))
                        .lineLimit(1)
                    if frame.width >= 60, frame.height >= 40 {
                        Text(sizeLine(node))
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(labelFill)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            if active {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(palette.scheme == .dark ? 0.12 : 0.2))
            }
        }
        .frame(width: max(frame.width, 0), height: max(frame.height, 0), alignment: .topLeading)
        .offset(x: frame.minX, y: frame.minY)
        .opacity(hovered == nil || active ? 1 : 0.45)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name) \(detail(node))")
        .accessibilityAddTraits(node.canEnter ? .isButton : [])
    }

    private func tip(_ node: DiskNode, at point: CGPoint, in size: CGSize) -> some View {
        let card = VStack(alignment: .leading, spacing: 2) {
            Text(node.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            Text(detail(node))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(palette.line, lineWidth: 1)
        }
        .shadow(color: .black.opacity(palette.scheme == .dark ? 0.35 : 0.12), radius: 8, y: 3)
        let below = point.y < 56
        let x = min(max(point.x, 88), max(88, size.width - 88))
        let y = below ? min(point.y + 28, size.height - 24) : max(24, point.y - 28)
        return card
            .position(x: x, y: y)
            .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.12), value: point.x)
            .animation(reduceMotion ? nil : .spring(duration: 0.26, bounce: 0.12), value: point.y)
    }

    private func sizeLine(_ node: DiskNode) -> String {
        (node.partial ? L("约 ") : "") + ByteText.string(node.bytes)
    }

    private func detail(_ node: DiskNode) -> String {
        let share = parentBytes > 0 ? Double(node.bytes) / Double(parentBytes) * 100 : 0
        return L("%@，占 %@", sizeLine(node), String(format: "%.1f%%", share))
    }

    private func find(_ path: String, in level: [DiskNode]) -> DiskNode? {
        for node in level {
            if node.path == path { return node }
            if let found = find(path, in: node.children) { return found }
        }
        return nil
    }

    /// 相邻方块各退半个缝，缝宽 3pt。
    private static func split(_ rect: CGRect) -> CGRect {
        let next = rect.insetBy(dx: 1.5, dy: 1.5)
        guard next.width >= 1, next.height >= 1 else { return rect }
        return next
    }
}

private struct SkeletonWave: ViewModifier {
    var index: Int
    var active: Bool
    var reduceMotion: Bool
    @State private var low = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (reduceMotion ? 0.8 : (low ? 0.52 : 1)) : 1)
            .task(id: active) {
                guard active, !reduceMotion else { return }
                try? await Task.sleep(nanoseconds: UInt64(index) * 90_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    low = true
                }
            }
    }
}

private struct DiskMapLoading: View {
    var nodes: [DiskNode]
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cellFill: Color {
        palette.scheme == .dark
            ? Color(red: 0.23, green: 0.27, blue: 0.29)
            : Color(red: 206 / 255, green: 211 / 255, blue: 214 / 255)
    }

    private var labelFill: Color {
        palette.scheme == .dark
            ? Color.white.opacity(0.92)
            : Color(red: 33 / 255, green: 41 / 255, blue: 44 / 255)
    }

    var body: some View {
        GeometryReader { geo in
            let inputs = DiskMap.rootNames.map { TreemapInput(id: $0, title: $0, value: 1) }
            let tiles = TreemapLayout.tiles(inputs, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    let frame = split(tile.rect)
                    let ready = nodes.first { $0.name == tile.title }
                    tileFace(name: tile.title, ready: ready, index: index)
                        .frame(width: max(frame.width, 0), height: max(frame.height, 0), alignment: .topLeading)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("正在统计启动磁盘"))
    }

    private func tileFace(name: String, ready: DiskNode?, index: Int) -> some View {
        let pending = ready == nil
        return ZStack(alignment: .topLeading) {
            cellFill
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                Text(ready.map(sizeLine) ?? L("计算中"))
                    .lineLimit(1)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(labelFill.opacity(pending ? 0.7 : 1))
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        .clipped()
        .modifier(SkeletonWave(index: index, active: pending, reduceMotion: reduceMotion))
    }

    private func sizeLine(_ node: DiskNode) -> String {
        (node.partial ? L("约 ") : "") + ByteText.string(node.bytes)
    }

    private func split(_ rect: CGRect) -> CGRect {
        let next = rect.insetBy(dx: 1.5, dy: 1.5)
        guard next.width >= 1, next.height >= 1 else { return rect }
        return next
    }
}

private struct DiskPathBar: View {
    var crumbs: [DiskNode]
    var currentBytes: String?
    var reduceMotion: Bool
    var onSelect: (String?) -> Void
    @Environment(\.palette) private var palette
    @State private var hovered: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            crumb(title: L("启动盘"), path: nil, current: crumbs.isEmpty)
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.line)
                    .padding(.horizontal, 6)
                    .accessibilityHidden(true)
                crumb(title: node.name, path: node.path, current: index == crumbs.count - 1)
                    .transition(reduceMotion ? .identity : .asymmetric(
                        insertion: .modifier(active: CrumbFade(amount: 1, distance: -8), identity: CrumbFade(amount: 0, distance: 0)),
                        removal: .modifier(active: CrumbFade(amount: 1, distance: -4), identity: CrumbFade(amount: 0, distance: 0))
                    ))
            }
            Spacer(minLength: 12)
            if let currentBytes {
                Text(currentBytes)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.ink)
            }
        }
        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.24), value: crumbs.map(\.path))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("路径"))
    }

    private func crumb(title: String, path: String?, current: Bool) -> some View {
        let shown = Text(title)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .underline(hovered == (path ?? "/"), color: palette.ink)
            .foregroundStyle(current ? palette.ink : palette.ink.opacity(0.55))
        return Group {
            if current {
                shown.accessibilityAddTraits(.isSelected)
            } else {
                Button {
                    onSelect(path)
                } label: {
                    shown
                }
                .buttonStyle(PlainPressStyle())
                .onHover { inside in hovered = inside ? (path ?? "/") : (hovered == (path ?? "/") ? nil : hovered) }
                .pointerStyle(.link)
            }
        }
        .accessibilityLabel(title)
    }
}

private struct CrumbFade: ViewModifier {
    var amount: CGFloat
    var distance: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .offset(x: distance * amount)
            .blur(radius: 2 * amount)
    }
}

struct DiskMapTool: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var volume = VolumeSpace(name: L("启动磁盘"), total: 0, available: 0)
    @State private var nodes: [DiskNode] = []
    @State private var scanning = true
    @State private var fullDisk = true
    @State private var focusPath: String?

    private var focusChain: [DiskNode] {
        guard let focusPath else { return [] }
        return chain(to: focusPath, in: nodes)
    }

    private var visible: [DiskNode] {
        if let current = focusChain.last {
            return current.children.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        }
        return nodes.filter { $0.bytes > 0 }
    }

    private var listed: [DiskNode] {
        if focusPath != nil { return visible }
        guard scanning else { return nodes }
        return DiskMap.rootNames.map { name in
            nodes.first { $0.name == name }
                ?? DiskNode(name: name, path: "/\(name)", bytes: 0, partial: false, pending: true, children: [])
        }
    }

    private var chartParentBytes: UInt64 {
        if let current = focusChain.last { return current.bytes }
        return visible.reduce(0) { $0 + $1.bytes }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(
                    title: L("启动磁盘"),
                    subtitle: L("按目录看空间用在哪。各项加起来不一定等于已用，系统快照不在这些目录里。"),
                    help: FeatureHelp.disk
                )
                Text(L("已用 %@ / %@，可用 %@", ByteText.string(volume.used), ByteText.string(volume.total), ByteText.string(volume.available)))
                    .font(.system(size: 13, weight: .semibold))
                if !fullDisk {
                    WorkspacePanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("没有完全磁盘访问权限。启动盘总容量、应用程序大小和上次使用时间不用它也能读到。邮件、信息、Safari 这些受保护的目录会计得偏小。系统不会弹出授权框，要在系统设置里打开。"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(L("打开完全磁盘访问权限")) { openFullDiskAccess() }
                                .buttonStyle(TintCapsuleStyle())
                        }
                    }
                }
                DiskPathBar(
                    crumbs: focusChain,
                    currentBytes: focusChain.last.map { ($0.partial ? L("约 ") : "") + ByteText.string($0.bytes) },
                    reduceMotion: reduceMotion,
                    onSelect: { move(to: $0) }
                )
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.line).frame(height: 1) }
                if scanning {
                    let pending = DiskMap.rootNames.filter { name in !nodes.contains { $0.name == name } }
                    if !pending.isEmpty {
                        Text(L("正在统计 %@。", pending.joined(separator: L("、"))))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Group {
                    if visible.isEmpty && scanning {
                        DiskMapLoading(nodes: nodes)
                            .transition(.opacity)
                    } else if !visible.isEmpty {
                        DiskMapChart(nodes: visible, parentBytes: chartParentBytes) { node in
                            move(to: node.path)
                        }
                        .id(focusPath ?? "/")
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity
                        ))
                    }
                }
                .frame(height: 420)
                .frame(maxWidth: .infinity)
                .animation(reduceMotion ? nil : .spring(duration: 0.62, bounce: 0.06), value: focusPath)
                if scanning || !listed.isEmpty {
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(listed) { node in
                            row(node)
                        }
                    }
                }
                }
            }
            .padding(.bottom, 20)
        }
        .onExitCommand { back() }
        .task { await load() }
    }

    private func row(_ node: DiskNode) -> some View {
        let body = HStack(spacing: 8) {
            Text(node.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(node.pending ? L("计算中") : (node.partial ? L("约 ") : "") + ByteText.string(node.bytes))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            if node.canEnter {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        return Group {
            if node.canEnter {
                Button { move(to: node.path) } label: { body }
                    .buttonStyle(PlainPressStyle())
            } else {
                body
            }
        }
    }


    private func move(to path: String?) {
        focusPath = path
    }

    private func back() {
        guard focusPath != nil else { return }
        if focusChain.count <= 1 {
            focusPath = nil
        } else {
            focusPath = focusChain.dropLast().last?.path
        }
    }

    private func chain(to path: String, in level: [DiskNode]) -> [DiskNode] {
        for node in level {
            if node.path == path { return [node] }
            let prefix = node.path + "/"
            if path.hasPrefix(prefix) || path.hasPrefix(node.path + "#") {
                let nested = chain(to: path, in: node.children)
                if !nested.isEmpty { return [node] + nested }
            }
        }
        return []
    }

    private func load() async {
        scanning = true
        async let space = Task.detached { DiskMap.volume() }.value
        async let access = Task.detached { DiskMap.hasFullDiskAccess() }.value
        volume = await space
        fullDisk = await access
        nodes = []
        let names = DiskMap.rootNames
        let control = AllocatedSize.ScanControl()
        await withTaskCancellationHandler {
            await withTaskGroup(of: DiskNode.self) { group in
                var next = 0
                let width = min(1, names.count)
                for _ in 0..<width {
                    let name = names[next]
                    next += 1
                    group.addTask { await Task.detached { DiskMap.measure(name, control: control) }.value }
                }
                for await node in group {
                    if Task.isCancelled { break }
                    nodes.append(node)
                    if next < names.count {
                        let name = names[next]
                        next += 1
                        group.addTask { await Task.detached { DiskMap.measure(name, control: control) }.value }
                    }
                }
            }
        } onCancel: {
            control.stop()
        }
        guard !Task.isCancelled else { return }
        nodes.sort { $0.bytes > $1.bytes }
        scanning = false
    }

    private func openFullDiskAccess() {
        let addresses = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ]
        for address in addresses {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return }
        }
    }
}

struct MemoryMapTool: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var report: MemoryReport?
    @State private var loading = false
    @State private var message = ""
    @State private var donut = false
    @State private var focusSlice: String?
    @State private var pending: MemoryApp?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("内存分布"),
                subtitle: L("应用、联动、压缩和缓存文件分开算，口径跟活动监视器一致。下面是按应用合计的实际占用。"),
                help: FeatureHelp.memory,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading
            ) {
                Task { await reload() }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let report {
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(report.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Text(L("物理内存 %@", ByteText.string(report.total)))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer(minLength: 8)
                            Button(donut ? L("条形图") : L("环形图")) {
                                donut.toggle()
                            }
                            .buttonStyle(FieldMenuStyle())
                            .accessibilityLabel(donut ? L("切换为条形图") : L("切换为环形图"))
                        }
                        Group {
                            if donut {
                                MemoryDonut(slices: report.slices, total: report.total, color: color, hovered: $focusSlice)
                                    .frame(maxWidth: .infinity)
                                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            } else {
                                MemorySplitBar(slices: report.slices, color: color, hovered: $focusSlice)
                                    .transition(.opacity)
                            }
                        }
                        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.4), value: donut)
                        ForEach(report.slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(color(slice.id)).frame(width: 8, height: 8)
                                Text(slice.title)
                                    .font(.system(size: 13, weight: focusSlice == slice.id ? .semibold : .regular))
                                Spacer()
                                Text(ByteText.string(slice.bytes))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                focusSlice == slice.id ? palette.accentSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .opacity(focusSlice == nil || focusSlice == slice.id ? 1 : 0.72)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                if inside { focusSlice = slice.id }
                                else if focusSlice == slice.id { focusSlice = nil }
                            }
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: focusSlice)
                        }
                    }
                }
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("占得多的应用"))
                            .font(.system(size: 13, weight: .semibold))
                        if report.apps.isEmpty {
                            Text(L("没有读到应用占用。"))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(report.apps) { app in
                                memoryRow(app)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("退出这个应用"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(L("退出"), role: .destructive) {
                if let pending { Task { await quit(pending) } }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(pending.map { L("退出「%@」。没保存的内容会丢失。", $0.name) } ?? "")
        }
        .task { await reload() }
    }

    private func memoryRow(_ app: MemoryApp) -> some View {
        HStack(spacing: 12) {
            if app.path.isEmpty {
                Image(systemName: "app")
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
            } else {
                AppBundleIcon(path: app.path)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(ByteText.string(app.bytes))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(cpuText(app.cpu))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
                .accessibilityLabel("CPU \(cpuText(app.cpu))")
            if canQuit(app) {
                Button(L("退出")) { pending = app }
                    .buttonStyle(FieldMenuStyle())
            }
        }
        .padding(.vertical, 4)
    }

    private func cpuText(_ cpu: Double) -> String {
        if cpu >= 10 { return String(format: "%.0f%%", cpu) }
        return String(format: "%.1f%%", cpu)
    }

    private func canQuit(_ app: MemoryApp) -> Bool {
        if app.name == "MacBJ" || app.name == "泊位" || app.path.contains("泊位.app") { return false }
        if SpeedTune.protected.contains(app.name) { return false }
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let pids = app.pids.isEmpty ? [app.pid] : app.pids
        return pids.contains { $0 > 1 && $0 != selfPid }
    }

    private func color(_ id: String) -> Color {
        switch id {
        case "app": palette.accent
        case "wired": palette.ink.opacity(0.62)
        case "compressed": palette.accent.opacity(0.45)
        case "cached": palette.ink.opacity(0.24)
        default: palette.ink.opacity(0.1)
        }
    }

    private func reload() async {
        loading = true
        let next = await Task.detached { MemoryMap.snapshot() }.value
        report = next
        message = ""
        loading = false
    }

    private func quit(_ app: MemoryApp) async {
        pending = nil
        if app.path.hasSuffix(".app"),
           let identifier = Bundle(path: app.path)?.bundleIdentifier,
           identifier != "app.macbj.desktop" {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            if !running.isEmpty {
                running.forEach { $0.terminate() }
                message = L("已要求「%@」退出。", app.name)
                try? await Task.sleep(for: .milliseconds(400))
                await reload()
                return
            }
        }
        let selfPid = ProcessInfo.processInfo.processIdentifier
        let pids = app.pids.isEmpty ? [app.pid] : app.pids
        do {
            var sent = false
            for pid in pids where pid > 1 && pid != selfPid {
                try SpeedTune.quit(pid: pid, name: app.name)
                sent = true
            }
            message = sent ? L("已要求「%@」退出。", app.name) : L("不能退出这个进程。")
            try? await Task.sleep(for: .milliseconds(300))
            await reload()
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct MemorySplitBar: View {
    var slices: [MemorySlice]
    var color: (String) -> Color
    @Binding var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shown = slices.filter { $0.bytes > 0 }
        let total = max(shown.reduce(UInt64(0)) { $0 + $1.bytes }, 1)
        GeometryReader { geo in
            let gaps = CGFloat(max(0, shown.count - 1)) * 3
            let usable = max(0, geo.size.width - gaps)
            HStack(spacing: 3) {
                ForEach(shown) { slice in
                    let width = usable * CGFloat(slice.bytes) / CGFloat(total)
                    segment(slice, width: width)
                }
            }
            .frame(width: geo.size.width, height: 40, alignment: .leading)
            .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.4), value: shown.map(\.bytes))
        }
        .frame(height: 40)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("内存分布条"))
    }

    private func segment(_ slice: MemorySlice, width: CGFloat) -> some View {
        let active = hovered == slice.id
        let dim = hovered != nil && !active
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color(slice.id))
            if width >= 70 {
                Text(slice.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(lightLabel(slice.id) ? Color(red: 0.13, green: 0.16, blue: 0.17) : Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: max(width, 0), height: 40)
        .opacity(dim ? 0.35 : 1)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = slice.id }
            else if hovered == slice.id { hovered = nil }
        }
        .help("\(slice.title) \(ByteText.string(slice.bytes))")
        .accessibilityLabel("\(slice.title) \(ByteText.string(slice.bytes))")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovered)
    }

    private func lightLabel(_ id: String) -> Bool {
        id == "cached" || id == "free"
    }
}

private struct MemoryDonut: View {
    var slices: [MemorySlice]
    var total: UInt64
    var color: (String) -> Color
    @Binding var hovered: String?
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0

    private let canvas = CGSize(width: 400, height: 340)
    private var ringCenter: CGPoint { CGPoint(x: canvas.width / 2, y: canvas.height / 2) }
    private let ringRadius: CGFloat = 85

    var body: some View {
        let shown = slices.filter { $0.bytes > 0 }
        let sum = max(shown.reduce(UInt64(0)) { $0 + $1.bytes }, 1)
        let drawn = arcs(shown, sum: sum)
        let focus = drawn.first { $0.id == hovered }
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 24)
                .frame(width: ringRadius * 2, height: ringRadius * 2)
                .position(ringCenter)
            ForEach(drawn) { arc in
                let active = hovered == arc.id
                let grown = active ? 1 : 0
                DonutWedge(
                    start: arc.start,
                    end: min(arc.end, max(arc.start, sweep)),
                    lift: active ? 4 : 0,
                    outerRadius: ringRadius + 12 + CGFloat(grown) * 2,
                    innerRadius: ringRadius - 12 - CGFloat(grown)
                )
                .fill(color(arc.id))
                .opacity(hovered == nil || active ? 1 : 0.62)
                .overlay {
                    if active {
                        DonutWedge(
                            start: arc.start,
                            end: min(arc.end, max(arc.start, sweep)),
                            lift: 4,
                            outerRadius: ringRadius + 14,
                            innerRadius: ringRadius - 13
                        )
                        .fill(Color.white.opacity(palette.scheme == .dark ? 0.14 : 0.22))
                    }
                }
                .allowsHitTesting(false)
            }
            ForEach(drawn) { arc in
                if showsLabel(arc) {
                    label(arc, active: hovered == arc.id)
                        .position(labelPoint(arc, active: hovered == arc.id))
                        .opacity(hovered == nil || hovered == arc.id ? 1 : 0.55)
                        .allowsHitTesting(false)
                }
            }
            VStack(spacing: 2) {
                Text(focus?.title ?? L("合计"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(ByteText.string(focus?.bytes ?? total))
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.numericText())
            }
            .position(ringCenter)
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hovered)
        }
        .frame(width: canvas.width, height: canvas.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let next: String?
            if case .active(let point) = phase {
                next = hit(point, arcs: drawn)
            } else {
                next = nil
            }
            if hovered != next { hovered = next }
        }
        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.26), value: hovered)
        .onAppear {
            if reduceMotion {
                sweep = 1
            } else {
                withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.72)) {
                    sweep = 1
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focus.map { L("%@ %@", $0.title, ByteText.string($0.bytes)) } ?? L("内存环形图，合计 %@", ByteText.string(total)))
    }

    private func label(_ arc: DonutArc, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color(arc.id))
                .frame(width: 6, height: 6)
            Text(arc.title)
                .font(.system(size: 12, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? palette.ink : Color.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background {
            if active {
                Capsule()
                    .fill(palette.surface)
                    .shadow(color: .black.opacity(palette.scheme == .dark ? 0.35 : 0.12), radius: 6, y: 2)
            }
        }
    }

    private func showsLabel(_ arc: DonutArc) -> Bool {
        guard sweep + 0.001 >= arc.end else { return false }
        return arc.span >= 0.06 || hovered == arc.id
    }

    private func labelPoint(_ arc: DonutArc, active: Bool) -> CGPoint {
        let theta = arc.mid * 2 * .pi - .pi / 2
        let cosine = cos(theta)
        let sine = sin(theta)
        let size = labelSize(arc.title)
        let radial = abs(cosine) * size.width / 2 + abs(sine) * size.height / 2
        let radius = ringRadius + 12 + (active ? 6 : 0) + 10 + radial
        return CGPoint(x: ringCenter.x + cosine * radius, y: ringCenter.y + sine * radius)
    }

    private func labelSize(_ title: String) -> CGSize {
        CGSize(width: CGFloat(title.count) * 12 + 27, height: 22)
    }

    private func hit(_ point: CGPoint, arcs: [DonutArc]) -> String? {
        let dx = point.x - ringCenter.x
        let dy = point.y - ringCenter.y
        let distance = hypot(dx, dy)
        if distance >= ringRadius - 16, distance <= ringRadius + 20 {
            var turn = (atan2(dy, dx) + .pi / 2) / (2 * .pi)
            if turn < 0 { turn += 1 }
            if turn >= 1 { turn -= 1 }
            if let match = arcs.first(where: { turn >= $0.start && turn <= $0.end }) {
                return match.id
            }
        }
        return arcs.first { arc in
            showsLabel(arc) && labelFrame(arc).insetBy(dx: -8, dy: -6).contains(point)
        }?.id
    }

    private func labelFrame(_ arc: DonutArc) -> CGRect {
        let active = hovered == arc.id
        let size = labelSize(arc.title)
        let point = labelPoint(arc, active: active)
        return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }

    private func arcs(_ slices: [MemorySlice], sum: UInt64) -> [DonutArc] {
        let gap: CGFloat = slices.count > 1 ? 0.008 : 0
        var cursor: CGFloat = 0
        return slices.map { slice in
            let share = CGFloat(slice.bytes) / CGFloat(sum)
            let start = cursor + gap / 2
            let end = cursor + max(share - gap / 2, 0)
            cursor += share
            return DonutArc(id: slice.id, title: slice.title, bytes: slice.bytes, start: start, end: end)
        }
    }
}

private struct DonutArc: Identifiable {
    var id: String
    var title: String
    var bytes: UInt64
    var start: CGFloat
    var end: CGFloat
    var span: CGFloat { end - start }
    var mid: CGFloat { (start + end) / 2 }
}

private struct DonutWedge: Shape {
    var start: CGFloat
    var end: CGFloat
    var lift: CGFloat
    var outerRadius: CGFloat
    var innerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>> {
        get { AnimatablePair(start, AnimatablePair(end, AnimatablePair(lift, AnimatablePair(outerRadius, innerRadius)))) }
        set {
            start = newValue.first
            end = newValue.second.first
            lift = newValue.second.second.first
            outerRadius = newValue.second.second.second.first
            innerRadius = newValue.second.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard end > start else { return Path() }
        let mid = (start + end) / 2
        let theta = mid * 2 * .pi - .pi / 2
        let center = CGPoint(
            x: rect.midX + cos(theta) * lift,
            y: rect.midY + sin(theta) * lift
        )
        var path = Path()
        path.addArc(
            center: center,
            radius: max(outerRadius, 1),
            startAngle: .radians(start * 2 * .pi - .pi / 2),
            endAngle: .radians(end * 2 * .pi - .pi / 2),
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: max(innerRadius, 1),
            startAngle: .radians(end * 2 * .pi - .pi / 2),
            endAngle: .radians(start * 2 * .pi - .pi / 2),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

struct AppUninstallTool: View {
    @Environment(\.palette) private var palette
    @State private var apps: [InstalledApp] = []
    @State private var query = ""
    @State private var loading = true
    @State private var message = ""
    @State private var pending: InstalledApp?

    private var visible: [InstalledApp] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedStandardContains(text) || $0.bundleID.localizedStandardContains(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("卸载应用"),
                subtitle: L("移到废纸篓，并带走用户目录里只属于它的偏好、缓存和支持文件。和别的应用共用的文件会留下。"),
                help: FeatureHelp.uninstall,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading
            ) {
                Task { await reload() }
            }
            TextField(L("搜索应用或包标识"), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if loading && visible.isEmpty {
                UninstallLoading()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { app in
                            appRow(app)
                            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
                if visible.isEmpty {
                    Text(apps.isEmpty ? L("没有找到应用程序文件夹里的应用。") : L("没有匹配的应用。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("卸载这个应用"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(L("移到废纸篓"), role: .destructive) {
                if let pending { Task { await uninstall(pending) } }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(pending.map(confirm) ?? "")
        }
        .task { await reload() }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AppBundleIcon(path: app.path)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 14, weight: .semibold))
                Text(detail(app))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if app.removable {
                Button(L("卸载")) { pending = app }
                    .buttonStyle(FieldMenuStyle())
            } else {
                Text(app.reason ?? L("不能卸载"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private func detail(_ app: InstalledApp) -> String {
        let size = app.bytes.map { ByteText.string($0) } ?? L("计算大小")
        let version = app.version.isEmpty ? "" : " · \(app.version)"
        let used = app.lastUsed.map { L("上次使用 %@", LastUsedText.string($0)) } ?? L("没有使用记录")
        let leftover = app.leftovers.isEmpty ? L("没有单独的残留") : L("%lld 项残留", app.leftovers.count)
        return "\(size)\(version) · \(used) · \(leftover)"
    }

    private func confirm(_ app: InstalledApp) -> String {
        if app.leftovers.isEmpty {
            return L("把「%@」移到废纸篓。没有找到只属于它的残留。", app.name)
        }
        let names = app.leftovers.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: L("、"))
        let more = app.leftovers.count > 5 ? L(" 等 %lld 项", app.leftovers.count) : ""
        return L("把「%@」和这些残留一起移到废纸篓：%@%@。", app.name, names, more)
    }

    private func reload() async {
        loading = true
        message = ""
        let listed = await Task.detached { AppUninstall.inventory() }.value
        let used = await Task.detached { AppUninstall.lastUsed(paths: listed.map(\.path)) }.value
        apps = listed.map { app in
            var copy = app
            copy.lastUsed = used[app.path]
            return copy
        }
        loading = false
        let control = AllocatedSize.ScanControl()
        await withTaskCancellationHandler {
            for app in listed {
                if Task.isCancelled { break }
                let bytes = await Task.detached { AppUninstall.allocatedSize(app.path, control: control) }.value
                if Task.isCancelled { break }
                if let index = apps.firstIndex(where: { $0.path == app.path }) {
                    apps[index].bytes = bytes
                }
            }
        } onCancel: {
            control.stop()
        }
    }

    private func uninstall(_ app: InstalledApp) async {
        pending = nil
        do {
            try await AppQuit.waitUntilQuit(bundleID: app.bundleID)
            try await Task.detached { try AppUninstall.trash(app) }.value
            message = L("「%@」已移到废纸篓。", app.name)
            await reload()
        } catch let error as ToolError {
            message = error.text
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct UninstallLoading: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("正在读取应用"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.ink.opacity(0.08))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.ink.opacity(0.1))
                            .frame(width: 132, height: 12)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(palette.ink.opacity(0.06))
                            .frame(width: 220, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .modifier(SkeletonWave(index: index, active: true, reduceMotion: reduceMotion))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("正在读取应用"))
    }
}

private struct AppBundleIcon: View {
    var path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }
}

private enum AppQuit {
    @MainActor
    static func waitUntilQuit(bundleID: String) async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
            try await Task.sleep(for: .milliseconds(120))
        }
        throw ToolError(L("应用没有退出，可能有没保存的内容。退出后再卸载。"))
    }
}

struct CacheCleanTool: View {
    @State private var targets: [CacheTarget] = []
    @State private var loading = false
    @State private var cleaning = false
    @State private var message = ""
    @State private var confirm = false

    private var selected: [CacheTarget] { targets.filter(\.selected) }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("清理缓存"),
                subtitle: L("只清理可以重新生成的缓存、日志和废纸篓。个人文件不在这里。"),
                help: FeatureHelp.caches,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading || cleaning
            ) {
                Task { await reload() }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 10) {
                    if targets.isEmpty, !loading {
                        Text(L("没有找到可清理的内容。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    if loading, targets.isEmpty {
                        Text(L("正在统计缓存、日志和废纸篓。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach($targets) { $target in
                        Toggle(isOn: $target.selected) {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.title)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(target.detail)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(target.pending ? L("计算中") : (target.partial ? L("约 ") : "") + ByteText.string(target.bytes))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    Button(cleaning ? L("正在清理") : L("清理选中")) { confirm = true }
                        .buttonStyle(TintCapsuleStyle())
                        .disabled(selected.isEmpty || cleaning || selected.contains(where: \.pending))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("清理选中的内容"), isPresented: $confirm, titleVisibility: .visible) {
            Button(L("清理"), role: .destructive) { Task { await clean() } }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(selected.isEmpty ? "" : L("将删除：%@。这些内容可以重新生成。", selected.map(\.title).joined(separator: L("、"))))
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        let found = await Task.detached { CacheClean.existing() }.value
        targets = found
        loading = false
        let ids = found.map(\.id)
        let control = AllocatedSize.ScanControl()
        await withTaskCancellationHandler {
            await withTaskGroup(of: (String, UInt64, Bool).self) { group in
                var next = 0
                for _ in 0..<min(2, ids.count) {
                    let id = ids[next]
                    next += 1
                    group.addTask {
                        let measured = await Task.detached { CacheClean.measure(id: id, control: control) }.value
                        return (id, measured.bytes, measured.complete)
                    }
                }
                for await item in group {
                    if Task.isCancelled { break }
                    if let index = targets.firstIndex(where: { $0.id == item.0 }) {
                        targets[index].bytes = item.1
                        targets[index].partial = !item.2
                        targets[index].pending = false
                    }
                    if next < ids.count {
                        let id = ids[next]
                        next += 1
                        group.addTask {
                            let measured = await Task.detached { CacheClean.measure(id: id, control: control) }.value
                            return (id, measured.bytes, measured.complete)
                        }
                    }
                }
            }
        } onCancel: {
            control.stop()
        }
    }

    private func clean() async {
        let ids = Set(selected.map(\.id))
        cleaning = true
        do {
            let freed = try await Task.detached { try CacheClean.clean(ids: ids) }.value
            message = L("已清理 %@。", ByteText.string(freed))
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
        cleaning = false
        await reload()
    }
}

struct SpeedTuneTool: View {
    @State private var report: MemoryReport?
    @State private var hogs: [SpeedHog] = []
    @State private var items: [SpeedLoginItem] = []
    @State private var loading = false
    @State private var busy = false
    @State private var message = ""
    @State private var pending: SpeedHog?

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("优化速度"),
                subtitle: L("释放未使用的内存、刷新 DNS、结束占资源的进程，以及开关用户自己的启动代理。"),
                help: FeatureHelp.speed,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading || busy
            ) {
                Task { await reload() }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report?.summary ?? L("正在读取内存。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button(busy ? L("正在执行") : L("释放内存")) { Task { await purge() } }
                            .buttonStyle(TintCapsuleStyle())
                            .disabled(busy)
                        Button(L("刷新 DNS")) { Task { await flushDNS() } }
                            .buttonStyle(FieldMenuStyle())
                            .disabled(busy)
                    }
                    Text(L("这两项会弹出系统密码框。取消后不会改任何东西。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("占资源的进程"))
                        .font(.system(size: 13, weight: .semibold))
                    if hogs.isEmpty {
                        Text(L("现在没有明显占着 CPU 或内存的进程。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(hogs) { hog in
                        HStack(spacing: 12) {
                            Text(String(format: "%.0f%%", hog.cpu))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hog.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(ByteText.string(hog.bytes))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L("结束")) { pending = hog }
                                .buttonStyle(FieldMenuStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("启动代理"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L("只列出用户目录里的启动代理。系统级服务和登录时打开的应用留在系统设置里。"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if items.isEmpty {
                        Text(L("没有用户启动代理。"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(items) { item in
                        Toggle(item.name, isOn: Binding(
                            get: { item.enabled },
                            set: { next in Task { await toggle(item, enabled: next) } }
                        ))
                        .font(.system(size: 13))
                    }
                    Button(L("打开系统设置里的登录项")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .buttonStyle(FieldMenuStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("结束这个进程"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(L("结束"), role: .destructive) {
                if let pending { Task { await quit(pending) } }
            }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(pending.map { L("结束「%@」。没保存的内容会丢失。", $0.name) } ?? "")
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        async let memory = Task.detached { MemoryMap.snapshot() }.value
        async let found = Task.detached { SpeedTune.hogs() }.value
        async let agents = Task.detached { SpeedTune.loginItems() }.value
        report = await memory
        hogs = await found
        items = await agents
        loading = false
    }

    private func purge() async {
        busy = true
        message = await SpeedTune.administrator("/usr/sbin/purge") ?? L("已要求系统释放未使用的内存。")
        busy = false
        await reload()
    }

    private func flushDNS() async {
        busy = true
        message = await SpeedTune.administrator("/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder") ?? L("已刷新 DNS 缓存。")
        busy = false
    }

    private func quit(_ hog: SpeedHog) async {
        pending = nil
        do {
            try SpeedTune.quit(pid: hog.pid, name: hog.name)
            message = L("已结束「%@」。", hog.name)
            await reload()
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
    }

    private func toggle(_ item: SpeedLoginItem, enabled: Bool) async {
        do {
            try SpeedTune.setAgent(label: item.label, enabled: enabled)
            if let index = items.firstIndex(where: { $0.path == item.path }) {
                items[index].enabled = enabled
            }
            message = enabled ? L("已启用「%@」。", item.name) : L("已停用「%@」。下次登录生效。", item.name)
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
    }
}
