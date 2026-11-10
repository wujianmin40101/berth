import AppKit
import SwiftUI

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
                Text(message).font(.system(size: 12)).textSecondaryStyle()
            }
            if let report {
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(report.summary)
                            .font(.system(size: 13))
                            .textSecondaryStyle()
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
                        .animation(reduceMotion ? nil : Motion.focus, value: donut)
                        ForEach(report.slices) { slice in
                            HStack(spacing: 8) {
                                Circle().fill(color(slice.id)).frame(width: 8, height: 8)
                                Text(slice.title)
                                    .font(.system(size: 13, weight: focusSlice == slice.id ? .semibold : .regular))
                                Spacer()
                                Text(ByteText.string(slice.bytes))
                                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                                    .textSecondaryStyle()
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
                            .animation(reduceMotion ? nil : Motion.color, value: focusSlice)
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
                                .textSecondaryStyle()
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
                    .textSecondaryStyle()
            } else {
                AppBundleIcon(path: app.path)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(ByteText.string(app.bytes))
                    .font(.system(size: 12))
                    .textSecondaryStyle()
            }
            Spacer(minLength: 8)
            Text(cpuText(app.cpu))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .textSecondaryStyle()
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
        if ProcessGuard.isSystemLocation(app.path) { return false }
        let pids = app.pids.isEmpty ? [app.pid] : app.pids
        return pids.contains { ProcessGuard.canStop(pid: $0) }
    }

    private func color(_ id: String) -> Color {
        switch id {
        case "app": palette.accentFill
        case "wired": palette.ink.opacity(0.62)
        case "compressed": palette.accentFill.opacity(0.45)
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
    @Environment(\.palette) private var palette
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
                    .foregroundStyle(lightLabel(slice.id) ? palette.chartInk : Color.white)
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
        .animation(reduceMotion ? nil : Motion.color, value: hovered)
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
                    .textSecondaryStyle()
                Text(ByteText.string(focus?.bytes ?? total))
                    .font(.system(size: 16, weight: .semibold))
                    .contentTransition(.numericText())
            }
            .position(ringCenter)
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : Motion.color, value: hovered)
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
        .animation(reduceMotion ? nil : Motion.focus, value: hovered)
        .onAppear {
            if reduceMotion {
                sweep = 1
            } else {
                withAnimation(Motion.enter) {
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
                .foregroundStyle(active ? palette.ink : palette.textSecondary)
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
