import AppKit
import SwiftUI

private struct DiskMapChart: View {
    var nodes: [DiskNode]
    var parentBytes: UInt64
    var onOpen: (DiskNode) -> Void
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: String?
    @State private var pointer: CGPoint?

    private var cellFill: Color { palette.chartTrack }
    private var labelFill: Color { palette.chartInk }

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
            .animation(reduceMotion ? nil : Motion.color, value: hovered)
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
                .textSecondaryStyle()
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
            .animation(reduceMotion ? nil : Motion.focus, value: point.x)
            .animation(reduceMotion ? nil : Motion.focus, value: point.y)
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

struct SkeletonWave: ViewModifier {
    var index: Int
    var active: Bool
    var reduceMotion: Bool
    @State private var low = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (reduceMotion ? 0.8 : (low ? 0.52 : 1)) : 1)
            .animation(active && !reduceMotion ? Motion.skeleton : nil, value: low)
            .task(id: active) {
                guard active, !reduceMotion else {
                    low = false
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(index) * 90_000_000)
                guard !Task.isCancelled else { return }
                low = true
            }
    }
}

private struct DiskMapLoading: View {
    var nodes: [DiskNode]
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cellFill: Color { palette.chartTrack }
    private var labelFill: Color { palette.chartInk }

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
        .animation(reduceMotion ? nil : Motion.focus, value: crumbs.map(\.path))
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
                                .textSecondaryStyle()
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
                            .textSecondaryStyle()
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
                .animation(reduceMotion ? nil : Motion.focus, value: focusPath)
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
                .textSecondaryStyle()
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
