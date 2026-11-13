import AppKit
import SwiftUI

struct PhoneStagePage: View {
    var page: PhonePage
    var stage: PhoneStageSnapshot
    var reduceMotion: Bool
    var refresh: () -> Void
    @Environment(\.palette) private var palette
    @State private var selectedStep: String?
    @State private var pickedShot: URL?
    @State private var liveJPEG: Data?
    @State private var previewEpoch = 0
    @State private var previewUnavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(page.detail)
                .font(.system(size: 13))
                .textSecondaryStyle()
                .fixedSize(horizontal: false, vertical: true)
            switch page {
            case .screen:
                screenBody
            case .recover:
                recoveryBody
            case .read:
                shotGrid(stage.pages, empty: L("状态目录里还没有页面截图。"))
            case .gesture:
                gestureBody
            case .typing:
                shotGrid(stage.crops, empty: L("状态目录里没有文字切片。输入的原文不会写进画面状态。"))
            case .batch:
                batchBody
            case .list:
                listBody
            case .navigate:
                navigateBody
            case .reconnect:
                reconnectBody
            case .schedule:
                EmptyView()
            }
        }
        .task(id: previewKey) {
            guard page == .screen, !stage.paused else { return }
            liveJPEG = nil
            previewUnavailable = false
            let stateDir = PhoneUseLocation.state
            let checkout = PhoneUseLocation.checkout
            let preview = PhonePreview()
            await withTaskCancellationHandler {
                await preview.run(stateDir: stateDir, checkout: checkout) { data in
                    Task { @MainActor in
                        if stage.paused, stage.pauseReason != "device_locked" { return }
                        liveJPEG = data
                        previewUnavailable = false
                    }
                } onSignal: { signal in
                    Task { @MainActor in
                        switch signal {
                        case .waiting:
                            previewUnavailable = false
                        case .unavailable:
                            if liveJPEG == nil { previewUnavailable = true }
                        }
                    }
                }
            } onCancel: {
                preview.stop()
            }
        }
        .onChange(of: stage.paused) { _, paused in
            if paused, stage.pauseReason != "device_locked" {
                liveJPEG = nil
            }
        }
    }

    private var previewKey: Int {
        guard page == .screen, !stage.paused else { return -1 }
        return previewEpoch
    }

    private var chosenStep: PhoneTraceStep? {
        guard let selectedStep else { return nil }
        return stage.steps.first { $0.id == selectedStep }
    }

    private var screenBody: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                shell
                screenFacts
            }
            VStack(alignment: .leading, spacing: 14) {
                shell
                screenFacts
            }
        }
    }

    private var shell: some View {
        VStack(spacing: 12) {
            statusPill
            device
            toolbar
            if selectedStep != nil || pickedShot != nil {
                Button(L("回到实时")) {
                    selectedStep = nil
                    pickedShot = nil
                }
                .buttonStyle(TintCapsuleStyle())
            }
            Text(L("刷新会重新连接 USB 预览，不重启手机服务，也不向手机发送点击。"))
                .font(.system(size: 12))
                .textSecondaryStyle()
                .multilineTextAlignment(.center)
                .frame(width: 232)
        }
        .frame(width: 248)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Text(stage.model.isEmpty ? "iPhone" : stage.model)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.ink)
            HStack(spacing: 5) {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
                    .opacity(stage.live == .connecting && !reduceMotion ? 0.45 : 1)
                Text(liveLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(palette.surface, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(palette.line))
    }

    private var savedPreview: String {
        switch stage.live {
        case .connecting: return L("连接中")
        case .paused: return stage.pauseReason == "device_locked" ? L("等待解锁") : L("已暂停")
        case .cached: return L("最近画面")
        case .offline: return L("未连接")
        }
    }

    private var showingLive: Bool {
        chosenStep == nil && pickedShot == nil && liveJPEG != nil && !stage.paused
    }

    private var liveLabel: String {
        if let chosenStep { return stepTitle(chosenStep) }
        if pickedShot != nil { return L("保存的截图") }
        if showingLive { return L("实时") }
        if stage.paused { return stage.pauseReason == "device_locked" ? L("等待解锁") : L("已暂停") }
        if previewUnavailable { return L("画面暂不可用") }
        return L("连接中")
    }

    private var dot: Color {
        if showingLive { return palette.accentFill }
        if stage.paused { return palette.ink }
        return palette.textSecondary
    }

    private var device: some View {
        let width: CGFloat = 232
        let picture = stage.viewportWidth > 0 ? stage.viewportWidth : 393
        let tall = stage.viewportHeight > 0 ? stage.viewportHeight : 852
        let height = width / (picture / tall)
        return ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 196 / 255, green: 192 / 255, blue: 185 / 255),
                        Color(red: 104 / 255, green: 102 / 255, blue: 98 / 255),
                        Color(red: 177 / 255, green: 173 / 255, blue: 166 / 255),
                        Color(red: 85 / 255, green: 84 / 255, blue: 82 / 255),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            sideButtons
            screenFace
                .padding(7)
            if stage.shell == .island {
                Capsule()
                    .fill(Color(red: 0.012, green: 0.016, blue: 0.02))
                    .frame(width: 74, height: 22)
                    .padding(.top, 14)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("iPhone 实时屏幕"))
    }

    private var sideButtons: some View {
        ZStack {
            buttonStrip(x: -3, widths: [(0.15, 0.037), (0.23, 0.064), (0.32, 0.064)], leading: true)
            buttonStrip(x: 3, widths: [(0.26, 0.104)], leading: false)
        }
    }

    private func buttonStrip(x: CGFloat, widths: [(CGFloat, CGFloat)], leading: Bool) -> some View {
        GeometryReader { geo in
            ForEach(Array(widths.enumerated()), id: \.offset) { _, item in
                Capsule()
                    .fill(Color(red: 0.45, green: 0.44, blue: 0.42))
                    .frame(width: 4, height: geo.size.height * item.1)
                    .position(x: leading ? 2 + x : geo.size.width - 2 + x, y: geo.size.height * (item.0 + item.1 / 2))
            }
        }
        .allowsHitTesting(false)
    }

    private var screenFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.02, green: 0.024, blue: 0.035))
            facePicture
            if let mark = faceMark {
                PhoneGestureOverlay(mark: mark, fallbackWidth: stage.viewportWidth, fallbackHeight: stage.viewportHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            if stage.paused {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.52))
                VStack(spacing: 10) {
                    Image(systemName: "hand.raised")
                        .font(.system(size: 28, weight: .regular))
                    Text(L("请在手机上接管操作"))
                        .font(.system(size: 13, weight: .medium))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            if stage.operating {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(palette.accentFill.opacity(0.85), lineWidth: 2)
                    .opacity(reduceMotion ? 0.7 : 1)
            }
        }
    }

    private var faceSource: FaceSource {
        if let step = chosenStep, let shot = step.shot { return .file(shot) }
        if let pickedShot { return .file(pickedShot) }
        if let liveJPEG {
            if stage.paused, stage.pauseReason != "device_locked" { return .empty }
            return .jpeg(liveJPEG)
        }
        return .empty
    }

    private var faceMark: PhoneGestureMark? {
        if let step = chosenStep { return mark(for: step) }
        if showingLive { return stage.gestures.last }
        return nil
    }

    @ViewBuilder
    private var facePicture: some View {
        switch faceSource {
        case .file(let url):
            PhoneFileImage(url: url, mode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .jpeg(let data):
            PhoneJPEG(data: data)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        case .empty:
            emptyFace
        }
    }

    private func mark(for step: PhoneTraceStep) -> PhoneGestureMark? {
        guard let x = step.x, let y = step.y else { return nil }
        let width = stage.viewportWidth > 0 ? stage.viewportWidth : 393
        let height = stage.viewportHeight > 0 ? stage.viewportHeight : 852
        return PhoneGestureMark(id: 1, kind: "tap", x: x, y: y, x2: x, y2: y, at: 0, viewWidth: width, viewHeight: height)
    }

    private var emptyFace: some View {
        VStack(spacing: 10) {
            if previewUnavailable {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 28, weight: .regular))
                Text(L("画面暂不可用"))
                    .font(.system(size: 13, weight: .medium))
            } else {
                ProgressView()
                    .controlSize(.small)
                Text(L("正在连接"))
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .foregroundStyle(Color(red: 0.66, green: 0.67, blue: 0.69))
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            toolButton("arrow.clockwise", L("刷新连接"), enabled: true, action: {
                previewEpoch += 1
                refresh()
            })
            toolButton("house", L("回到主屏幕"), enabled: false, action: {})
            toolButton("camera", L("截图到剪贴板"), enabled: false, action: {})
        }
        .padding(4)
        .background(palette.surface, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(palette.line))
    }

    private func toolButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 34, height: 34)
                .foregroundStyle(palette.ink)
        }
        .buttonStyle(PlainPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(label)
    }

    private var screenFacts: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 8) {
                    fact(L("画面文件"), stage.pages.first?.name ?? L("还没有"))
                    fact(L("视口"), stage.viewportWidth > 0 ? "\(Int(stage.viewportWidth)) × \(Int(stage.viewportHeight))" : L("还没有"))
                    fact(L("会话"), stage.sessionOpen ? (stage.endpoint.isEmpty ? L("已连接会话") : stage.endpoint) : L("没有会话"))
                    if !stage.pauseReason.isEmpty {
                        fact(L("暂停原因"), pauseLabel(stage.pauseReason))
                    }
                }
            }
            if stage.pages.count > 1 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(stage.pages) { shot in
                            Button {
                                pickedShot = shot.url
                                selectedStep = nil
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    PhoneFileImage(url: shot.url, mode: .fit)
                                        .frame(width: 72, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(shot.stamp)
                                        .font(.system(size: 11))
                                        .foregroundStyle(pickedShot == shot.url ? palette.accentInk : palette.textSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            stepList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recoveryBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(stage.recoveryPhase.isEmpty ? L("没有进行中的恢复") : L("恢复进行到 %@", phaseLabel(stage.recoveryPhase)))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    HStack(spacing: 8) {
                        ForEach(["stopping", "starting", "serving"], id: \.self) { phase in
                            Text(phaseLabel(phase))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(stage.recoveryPhase == phase ? palette.accentInk : palette.textSecondary)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(stage.recoveryPhase == phase ? palette.accentSoft : palette.field, in: Capsule())
                        }
                    }
                    if stage.paused {
                        Text(stage.pauseReason == "device_locked" ? L("预览停在锁屏，解锁后刷新会重新读取。") : L("预览已暂停。认证完成后，刷新重新读取画面状态。"))
                            .font(.system(size: 13))
                            .foregroundStyle(palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(stage.startState.isEmpty ? L("没有启动任务。") : L("最近一次启动是 %@。", stateLabel(stage.startState)))
                        .font(.system(size: 13))
                        .textSecondaryStyle()
                }
            }
            jobList
        }
    }

    private var gestureBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let step = chosenStep, let url = step.shot ?? stage.pages.first?.url {
                PhoneMarkedShot(url: url, mark: mark(for: step), fallbackWidth: stage.viewportWidth, fallbackHeight: stage.viewportHeight)
                    .frame(maxWidth: 280)
            }
            stepList
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("进入假勤标在顶部固定的那枚假勤上。消息列表里的假勤会换位置，不标在那里。"))
                .font(.system(size: 13))
                .textSecondaryStyle()
                .fixedSize(horizontal: false, vertical: true)
            if stage.steps.isEmpty {
                Text(L("打卡日志里还没有进入页面、点击或切换账户。"))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
            }
            ForEach(stage.steps) { step in
                Button {
                    selectedStep = step.id
                    pickedShot = nil
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stepTitle(step))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedStep == step.id ? palette.accentInk : palette.ink)
                        Text(stepSubtitle(step))
                            .font(.system(size: 12))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(selectedStep == step.id ? palette.accentSoft : palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepTitle(_ step: PhoneTraceStep) -> String {
        switch step.kind {
        case "open": L("进入假勤")
        case "tap": step.detail == "punch-button" ? L("点击打卡按钮") : L("点击 %@", step.detail)
        case "switch": L("切换账户")
        case "recognize": L("识别到 %@", step.detail)
        case "page": L("看到 %@", step.detail)
        case "account": L("当前账户 %@", step.detail)
        default: step.detail
        }
    }

    private func stepSubtitle(_ step: PhoneTraceStep) -> String {
        let time = step.at.formatted(date: .omitted, time: .standard)
        if step.kind == "switch" || step.kind == "recognize" || step.kind == "account" {
            return "\(time)  \(step.detail)"
        }
        if let x = step.x, let y = step.y {
            return "\(time)  (\(Int(x)), \(Int(y)))"
        }
        return "\(time)  \(step.detail)"
    }

    private var batchBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            if stage.steps.isEmpty && stage.jobs.isEmpty {
                Text(L("还没有可以串起来的点击或启动步骤。"))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
            }
            if !stage.steps.isEmpty {
                stepList
            }
            jobList
        }
    }

    private var listBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(stage.pages.isEmpty
                         ? L("还没有采集到页面截图。")
                         : L("%d 张页面截图，从 %@ 到 %@。", stage.pages.count, stage.pages.last?.stamp ?? "", stage.pages.first?.stamp ?? ""))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(stage.droppedTwins > 0
                         ? L("同名的 jpg 去掉了 %d 张，只留 png。", stage.droppedTwins)
                         : L("没有同名的 jpg 需要去掉。"))
                        .font(.system(size: 13))
                        .textSecondaryStyle()
                }
            }
            shotGrid(stage.pages, empty: L("状态目录里还没有页面截图。"))
        }
    }

    private var navigateBody: some View {
        WorkspacePanel {
            VStack(alignment: .leading, spacing: 8) {
                fact(L("打包标识"), stage.bundleID.isEmpty ? L("还没有") : stage.bundleID)
                fact(L("本地端口"), stage.port > 0 ? "\(stage.port)" : L("还没有"))
                fact(L("会话"), stage.sessionOpen ? (stage.endpoint.isEmpty ? L("已连接会话") : stage.endpoint) : L("没有会话"))
                fact(L("启动"), stage.startState.isEmpty ? L("没有启动任务。") : stateLabel(stage.startState))
                if !stage.sourceDirectory.isEmpty {
                    Text(stage.sourceDirectory)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .textSecondaryStyle()
                }
            }
        }
    }

    private var reconnectBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 8) {
                    fact(L("会话"), stage.sessionOpen ? (stage.endpoint.isEmpty ? L("已连接会话") : stage.endpoint) : L("没有会话"))
                    fact(L("启动"), stage.startState.isEmpty ? L("没有启动任务。") : stateLabel(stage.startState))
                    fact(L("预览"), stage.paused ? (stage.pauseReason == "device_locked" ? L("等待解锁") : L("已暂停")) : savedPreview)
                    Text(L("刷新重新读取会话、启动任务和画面文件，不另开一条通道。"))
                        .font(.system(size: 13))
                        .textSecondaryStyle()
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: refresh) {
                        Text(L("刷新连接"))
                    }
                    .buttonStyle(TintCapsuleStyle())
                }
            }
        }
    }

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 8) {
            if stage.jobs.isEmpty {
                Text(L("没有任务记录。"))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
            }
            ForEach(stage.jobs.prefix(6)) { job in
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(actionLabel(job.action)) · \(stateLabel(job.state))")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.ink)
                        if !job.phase.isEmpty {
                            Text(L("阶段 %@", phaseLabel(job.phase)))
                                .font(.system(size: 13))
                                .foregroundStyle(palette.ink)
                        }
                        if !job.error.isEmpty {
                            Text(job.error)
                                .font(.system(size: 13))
                                .foregroundStyle(palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !job.created.isEmpty {
                            Text(jobClock(job.created))
                                .font(.system(size: 12))
                                .textSecondaryStyle()
                        }
                    }
                }
            }
        }
    }

    private func shotGrid(_ shots: [PhoneShot], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if shots.isEmpty {
                Text(empty)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(shots) { shot in
                        VStack(alignment: .leading, spacing: 6) {
                            PhoneFileImage(url: shot.url, mode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 220)
                                .background(palette.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            Text(shot.stamp)
                                .font(.system(size: 12))
                                .textSecondaryStyle()
                            Text(shot.name)
                                .font(.system(size: 11, design: .monospaced))
                                .textSecondaryStyle()
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12))
                .textSecondaryStyle()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pauseLabel(_ reason: String) -> String {
        switch reason {
        case "device_locked": L("锁屏")
        case "authentication": L("认证")
        default: L("画面暂不可用")
        }
    }

    private func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "stopping": L("停止中")
        case "starting": L("启动中")
        case "serving": L("服务中")
        default: phase
        }
    }

    private func stateLabel(_ state: String) -> String {
        switch state {
        case "queued": L("排队中")
        case "running": L("运行中")
        case "succeeded": L("已完成")
        case "failed": L("已失败")
        default: state
        }
    }

    private func actionLabel(_ action: String) -> String {
        switch action {
        case "start": L("启动")
        case "recover": L("恢复")
        case "fetch": L("获取")
        case "build": L("构建")
        case "stop": L("停止")
        default: action
        }
    }

    private func clock(_ ms: Int) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(date: .omitted, time: .standard)
    }

    private func jobClock(_ raw: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let date = fractional.date(from: raw) ?? plain.date(from: raw)
        return date?.formatted(date: .abbreviated, time: .shortened) ?? raw
    }
}

private enum FaceSource {
    case file(URL)
    case jpeg(Data)
    case empty
}

private struct PhoneJPEG: View {
    var data: Data

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PhoneFileImage: View {
    var url: URL
    var mode: ContentMode

    var body: some View {
        Group {
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: mode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PhoneGestureOverlay: View {
    var mark: PhoneGestureMark
    var fallbackWidth: Double
    var fallbackHeight: Double

    var body: some View {
        GeometryReader { geo in
            let width = mark.viewWidth > 0 ? mark.viewWidth : fallbackWidth
            let height = mark.viewHeight > 0 ? mark.viewHeight : fallbackHeight
            if width > 0, height > 0 {
                let start = CGPoint(x: mark.x / width * geo.size.width, y: mark.y / height * geo.size.height)
                let end = CGPoint(x: mark.x2 / width * geo.size.width, y: mark.y2 / height * geo.size.height)
                if mark.isDrag {
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                }
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .background(Circle().fill(Color.gray.opacity(0.4)))
                    .frame(width: 22, height: 22)
                    .position(mark.isDrag ? end : start)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PhoneMarkedShot: View {
    var url: URL
    var mark: PhoneGestureMark?
    var fallbackWidth: Double
    var fallbackHeight: Double

    var body: some View {
        ZStack {
            PhoneFileImage(url: url, mode: .fit)
            if let mark {
                PhoneGestureOverlay(mark: mark, fallbackWidth: fallbackWidth, fallbackHeight: fallbackHeight)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
