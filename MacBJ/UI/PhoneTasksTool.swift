import SwiftUI
import UniformTypeIdentifiers

struct PhoneTasksTool: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var desk = PhoneDesk(scriptReady: false, tasks: [], runs: [], savedProblem: nil)
    @State private var title = ""
    @State private var note = ""
    @State private var command = ""
    @State private var kind: PhoneTaskKind = .punchIn
    @State private var weekdays: Set<Int> = []
    @State private var clock = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var message = ""
    @State private var live = ""
    @State private var runningID: String?
    @State private var reports: [String: String] = [:]
    @State private var startedAt: [String: Date] = [:]
    @State private var busy = false
    @State private var showAll = false
    @State private var openedRun: String?
    @State private var pendingRun: PhoneTaskSnapshot?
    @State private var confirmRun = false
    @State private var pendingDelete: PhoneTaskSnapshot?
    @State private var tab: PhonePage = .schedule
    @State private var shown: PhonePage = .schedule
    @State private var fading = false
    @State private var swapToken = 0
    @State private var stage = PhoneStageSnapshot.empty
    @State private var checkoutText = ""
    @State private var checkoutOpen = PhoneUseLocation.checkoutOpen
    @State private var editorOpen = PhoneUseLocation.editorOpen
    @State private var logOpen = PhoneUseLocation.logOpen
    @State private var selectedTaskID = PhoneUseLocation.selectedTaskID
    @State private var shownTaskID: String?
    @State private var taskFading = false
    @State private var taskSwapToken = 0
    @State private var showIntro = false
    @State private var chooseCheckout = false
    @State private var installHost: PhoneAIHost = .codex
    @State private var taskHost: PhoneAIHost = .codex
    @State private var keptTaskPrompt = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("手机任务"),
                subtitle: L("连接 iPhone Use，看已有打卡任务的说明、日志和结果，也可以再加定时。"),
                help: FeatureHelp.phone,
                actionTitle: L("刷新"),
                action: reload
            )
            PhoneTabStrip(selection: tab, reduceMotion: reduceMotion, choose: choose)
            shownBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .opacity(fading ? 0 : 1)
                .animation(reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: fading)
                .offset(y: reduceMotion ? 0 : (fading ? 4 : 0))
                .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.2), value: fading)
                .blur(radius: reduceMotion ? 0 : (fading ? 2 : 0))
                .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: fading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(shown.heading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if checkoutText.isEmpty, let path = PhoneUseLocation.savedCheckout?.path {
                checkoutText = path
            }
            if !PhoneUseLocation.introSeen { showIntro = true }
            reload()
        }
        .confirmationDialog(
            L("立刻执行"),
            isPresented: $confirmRun,
            titleVisibility: .visible
        ) {
            Button(L("执行")) {
                let task = pendingRun
                pendingRun = nil
                if let task { start(task) }
            }
            Button(L("取消"), role: .cancel) { pendingRun = nil }
        } message: {
            Text(L("会马上执行「%@」。取消则不运行。", pendingRun?.title ?? ""))
        }
        .confirmationDialog(
            L("删除这个定时"),
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L("删除"), role: .destructive) { if let pendingDelete { delete(pendingDelete) } }
            Button(L("取消"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L("只会卸下这里新增的定时，不会改 iPhone Use 原来的上班和下班。"))
        }
        .fileImporter(isPresented: $chooseCheckout, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                checkoutText = url.path
                saveCheckout()
            }
        }
            if showIntro {
                PhoneEnableDialog(offersEnable: false, onConfirm: {}, onClose: {
                    PhoneUseLocation.introSeen = true
                    showIntro = false
                })
            }
        }
    }

    private func choose(_ next: PhonePage) {
        guard next != tab else { return }
        tab = next
        swapToken += 1
        let token = swapToken
        if reduceMotion {
            shown = next
            fading = false
            return
        }
        fading = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard token == swapToken else { return }
            shown = next
            try? await Task.sleep(for: .milliseconds(16))
            guard token == swapToken else { return }
            fading = false
        }
    }

    @ViewBuilder
    private var shownBody: some View {
        switch shown {
        case .schedule:
            scheduleScroll
        case .reconnect:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    linkPanel
                    PhoneStagePage(page: shown, stage: stage, reduceMotion: reduceMotion, refresh: reload)
                }
            }
        default:
            ScrollView {
                PhoneStagePage(page: shown, stage: stage, reduceMotion: reduceMotion, refresh: reload)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var scheduleScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                linkPanel
                scorePanel
                taskSwitcher
                editor
                logPanel
            }
            .onChange(of: desk.tasks.map(\.id)) { _, ids in
                let next = selectedTaskID.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first
                if selectedTaskID != next {
                    selectedTaskID = next
                    PhoneUseLocation.selectedTaskID = next
                }
                if shownTaskID != next {
                    shownTaskID = next
                    taskFading = false
                }
            }
        }
    }

    private var taskSwitcher: some View {
        VStack(alignment: .leading, spacing: 10) {
            if desk.tasks.isEmpty {
                Text(L("还没有定时。"))
                    .font(.system(size: 13))
                    .textSecondaryStyle()
            } else {
                PhoneTaskTabStrip(
                    tasks: desk.tasks,
                    selection: selectedTask?.id,
                    reduceMotion: reduceMotion,
                    choose: chooseTask
                )
                if let task = desk.tasks.first(where: { $0.id == (shownTaskID ?? selectedTask?.id) }) {
                    taskCard(task)
                        .opacity(taskFading ? 0 : 1)
                        .animation(reduceMotion ? .linear(duration: 0.12) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: taskFading)
                        .offset(y: reduceMotion ? 0 : (taskFading ? 4 : 0))
                        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.2), value: taskFading)
                        .blur(radius: reduceMotion ? 0 : (taskFading ? 2 : 0))
                        .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.18), value: taskFading)
                }
            }
        }
    }

    private func chooseTask(_ id: String) {
        guard id != selectedTaskID else { return }
        selectedTaskID = id
        PhoneUseLocation.selectedTaskID = id
        taskSwapToken += 1
        let token = taskSwapToken
        if reduceMotion {
            shownTaskID = id
            taskFading = false
            return
        }
        taskFading = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard token == taskSwapToken else { return }
            shownTaskID = id
            try? await Task.sleep(for: .milliseconds(16))
            guard token == taskSwapToken else { return }
            taskFading = false
        }
    }

    private var selectedTask: PhoneTaskSnapshot? {
        if let selectedTaskID, let task = desk.tasks.first(where: { $0.id == selectedTaskID }) {
            return task
        }
        return desk.tasks.first
    }

    private var linkPanel: some View {
        foldCard(
            title: L("脚本位置"),
            open: checkoutOpen,
            expandLabel: L("展开脚本位置"),
            collapseLabel: L("收起脚本位置"),
            toggle: {
                checkoutOpen.toggle()
                PhoneUseLocation.checkoutOpen = checkoutOpen
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                checkoutEditor
                installPrompt
            }
        } collapsed: {
            checkoutSummary
        }
    }

    private func foldCard<Expanded: View, Collapsed: View>(
        title: String,
        open: Bool,
        expandLabel: String,
        collapseLabel: String,
        toggle: @escaping () -> Void,
        @ViewBuilder expanded: () -> Expanded,
        @ViewBuilder collapsed: () -> Collapsed
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                disclosureLabel(title, open: open)
                if !open {
                    collapsed()
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            if open {
                expanded()
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -6)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Button(action: toggle) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.clear)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? collapseLabel : expandLabel)
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(palette.line)
                .allowsHitTesting(false)
        )
        .animation(foldAnimation(open), value: open)
    }

    private func foldAnimation(_ open: Bool) -> Animation {
        if reduceMotion { return Motion.reduced }
        return open
            ? Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
            : Motion.exit
    }

    private func disclosureLabel(_ title: String, open: Bool) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .rotationEffect(.degrees(open ? 180 : 0))
                .animation(reduceMotion ? nil : Animation.timingCurve(0.18, 0.89, 0.32, 1.15, duration: 0.26), value: open)
        }
        .contentShape(Rectangle())
    }

    private var checkoutSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(PhoneUseLocation.savedCheckout?.path ?? L("还没有设置脚本位置。"))
                .font(.system(size: 12, design: PhoneUseLocation.savedCheckout == nil ? .default : .monospaced))
                .foregroundStyle(PhoneUseLocation.savedCheckout == nil ? palette.textSecondary : palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(desk.scriptReady ? L("打卡脚本在。") : L("没有找到打卡脚本。"))
                .font(.system(size: 12))
                .foregroundStyle(desk.scriptReady ? palette.ink : palette.textSecondary)
            if let savedProblem = desk.savedProblem {
                Text(savedProblem)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
            }
        }
    }

    private var checkoutEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ToolTextField(title: L("脚本位置"), text: $checkoutText)
            HStack(spacing: 8) {
                Button(L("选择文件夹")) { chooseCheckout = true }
                    .buttonStyle(FieldMenuStyle())
                Button(L("保存")) { saveCheckout() }
                    .buttonStyle(TintCapsuleStyle())
            }
            if let path = PhoneUseLocation.savedCheckout?.path {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(L("还没有设置脚本位置。"))
                    .font(.system(size: 13))
                    .textSecondaryStyle()
            }
            Text(desk.scriptReady ? L("打卡脚本在。") : L("没有找到打卡脚本。"))
                .font(.system(size: 13))
                .foregroundStyle(desk.scriptReady ? palette.ink : palette.textSecondary)
            if let savedProblem = desk.savedProblem {
                Text(savedProblem)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink)
            }
        }
    }

    private var installPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("安装提示词"))
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 6)
            Text(L("整段复制到所选 AI 的聊天里。Codex、WorkBuddy、豆包工作按各自的安装方式。Muse、Claude Code、OpenCode、Cursor、DeepSeek、Grok 和其他 AI 不编造安装器。"))
                .font(.system(size: 12))
                .textSecondaryStyle()
                .fixedSize(horizontal: false, vertical: true)
            hostPicker($installHost)
            promptCard(PhoneTaskBrief.installPrompt(installHost), host: installHost) {
                LocalPasteboard.copy(PhoneTaskBrief.installPrompt(installHost))
                message = L("安装提示词已复制。贴到 %@ 的聊天里。", installHost.title)
            }
        }
    }

    private var scorePanel: some View {
        WorkspacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("执行记录"))
                    .font(.system(size: 13, weight: .semibold))
                let counts = PhoneTasks.counts(desk.runs)
                if counts.total == 0 {
                    Text(L("还没有执行记录。"))
                        .font(.system(size: 13))
                        .textSecondaryStyle()
                } else {
                    scoreBar(counts)
                    HStack(spacing: 16) {
                        score(L("成功"), counts.success, palette.accentInk)
                        score(L("未确认"), counts.unconfirmed, palette.ink)
                        score(L("已停止"), counts.stopped, palette.ink)
                        score(L("跳过"), counts.skipped, palette.textSecondary)
                        score(L("未结束"), counts.open, palette.textSecondary)
                    }
                }
            }
        }
    }

    private func scoreBar(_ counts: PhoneRunCounts) -> some View {
        let parts: [(Int, Color)] = [
            (counts.success, palette.accentFill),
            (counts.unconfirmed, palette.ink.opacity(0.55)),
            (counts.stopped, palette.ink.opacity(0.85)),
            (counts.skipped, palette.textSecondary.opacity(0.45)),
            (counts.open, palette.chartTrack),
        ]
        return GeometryReader { geo in
            let visible = parts.filter { $0.0 > 0 }
            let gaps = CGFloat(max(0, visible.count - 1)) * 2
            let usable = max(0, geo.size.width - gaps)
            HStack(spacing: 2) {
                ForEach(Array(visible.enumerated()), id: \.offset) { item in
                    item.element.1.frame(width: usable * CGFloat(item.element.0) / CGFloat(counts.total))
                }
            }
        }
        .frame(height: 8)
        .accessibilityLabel(L("成功 %lld，未确认 %lld，已停止 %lld，跳过 %lld，未结束 %lld", counts.success, counts.unconfirmed, counts.stopped, counts.skipped, counts.open))
    }

    private func score(_ name: String, _ count: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text("\(count)")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func taskCard(_ task: PhoneTaskSnapshot) -> some View {
        WorkspacePanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(task.title)
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(task.loaded ? L("已挂上") : (task.agent == nil ? L("没有定时文件") : L("未挂上")))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(task.loaded ? palette.accentInk : palette.textSecondary)
                }
                if !task.slots.isEmpty {
                    Text(PhoneTasks.scheduleText(task.slots))
                        .font(.system(size: 13, weight: .medium))
                    weekRail(task.slots)
                }
                Text(task.note)
                    .font(.system(size: 13))
                    .textSecondaryStyle()
                    .fixedSize(horizontal: false, vertical: true)
                if task.kind == .command, !task.command.isEmpty {
                    Text(task.command)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                if runningID == task.id {
                    Text(live.isEmpty ? L("正在执行") : live)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let report = reports[task.id], !report.isEmpty {
                    Text(report)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let latest = matched(task) {
                    HStack(spacing: 8) {
                        Text(L("最近一次"))
                            .font(.system(size: 12))
                            .textSecondaryStyle()
                        resultMark(latest.result)
                        Text(latest.lines.last?.message ?? "")
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                    }
                } else if task.kind != .command && reports[task.id] == nil && runningID != task.id {
                    Text(L("还没有分到这一班的记录。"))
                        .font(.system(size: 12))
                        .textSecondaryStyle()
                }
                ownedLog(task)
                HStack(spacing: 8) {
                    if task.owned || task.kind != .command {
                        Button(L("立刻执行")) {
                            pendingRun = task
                            confirmRun = true
                        }
                        .buttonStyle(TintCapsuleStyle())
                        .disabled(busy || (task.kind != .command && !desk.scriptReady))
                    }
                    if task.owned {
                        Button(task.enabled ? L("停用") : L("启用")) { toggle(task) }
                            .buttonStyle(FieldMenuStyle())
                        Spacer()
                        Button(L("删除")) { pendingDelete = task }
                            .buttonStyle(FieldMenuStyle())
                    } else if task.agent == nil {
                        Button(L("安装默认定时")) { installDefaults(task) }
                            .buttonStyle(TintCapsuleStyle())
                            .disabled(!desk.scriptReady || busy)
                    } else if !task.loaded {
                        Button(L("重新挂上")) { attach(task) }
                            .buttonStyle(FieldMenuStyle())
                    }
                }
            }
        }
    }

    private func weekRail(_ slots: [PhoneSlot]) -> some View {
        HStack(spacing: 4) {
            ForEach(PhoneSlot.weekOrder, id: \.self) { weekday in
                let on = slots.contains { $0.weekday == weekday }
                Text(dayMark(weekday))
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(on ? palette.accentInk : palette.textSecondary)
                    .background(on ? palette.accentSoft : palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func ownedLog(_ task: PhoneTaskSnapshot) -> some View {
        let tail = commandLog(task)
        if !tail.isEmpty {
            Text(tail)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(6)
        }
    }

    private var editor: some View {
        foldCard(
            title: L("交给 AI 写定时"),
            open: editorOpen,
            expandLabel: L("展开交给 AI 写定时"),
            collapseLabel: L("收起交给 AI 写定时"),
            toggle: {
                editorOpen.toggle()
                PhoneUseLocation.editorOpen = editorOpen
            }
        ) {
            editorBody
        } collapsed: {
            Text(L("写好名称和要做的事，展开后复制给 AI。"))
                .font(.system(size: 12))
                .textSecondaryStyle()
        }
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("AI 写好 scripts/tasks 里的文件后，点刷新。泊位按文件挂上定时，不用点增加。"))
                .font(.system(size: 12))
                .textSecondaryStyle()
                .fixedSize(horizontal: false, vertical: true)
            ToolTextField(title: L("名称"), text: $title)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("要做的事"))
                        .font(.system(size: 12, weight: .medium))
                        .textSecondaryStyle()
                    Text(L("写下这个定时到点要在手机上做什么。不写的话，自定义任务的提示词里没有这件事。"))
                        .font(.system(size: 12))
                        .textSecondaryStyle()
                        .fixedSize(horizontal: false, vertical: true)
                    TextEditor(text: $note)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 88)
                        .background(palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Picker(L("做什么"), selection: $kind) {
                    Text(L("上班打卡")).tag(PhoneTaskKind.punchIn)
                    Text(L("下班打卡")).tag(PhoneTaskKind.punchOut)
                    Text(L("自定义")).tag(PhoneTaskKind.command)
                }
                .pickerStyle(.segmented)
                Text(L("星期"))
                    .font(.system(size: 12, weight: .medium))
                    .textSecondaryStyle()
                Text(L("点选要执行的星期，再点一次就取消。"))
                    .font(.system(size: 12))
                    .textSecondaryStyle()
                PhoneWeekdayPicker(weekdays: $weekdays)
                Text(L("时间"))
                    .font(.system(size: 12, weight: .medium))
                    .textSecondaryStyle()
                DatePicker(L("时间"), selection: $clock, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                if overlapWarning {
                    Text(L("这个时间和已有任务重合，到点会各跑一次。"))
                        .font(.system(size: 12))
                        .textSecondaryStyle()
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !live.isEmpty {
                    Text(live)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.ink)
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L("任务提示词"))
                    .font(.system(size: 13, weight: .semibold))
                hostPicker($taskHost)
                if let prompt = displayedTaskPrompt {
                    promptCard(prompt, host: taskHost) { copyTaskPrompt(prompt) }
                } else {
                    Text(kind == .command
                        ? L("先写名称，写下要做的事，并至少选一个星期。不写要做的事，定时不知道干什么。")
                        : L("先写名称，并至少选一个星期。上班和下班会把打卡写进提示词。"))
                        .font(.system(size: 12))
                        .textSecondaryStyle()
                }
        }
    }

    private var logPanel: some View {
        foldCard(
            title: L("日志"),
            open: logOpen,
            expandLabel: L("展开日志"),
            collapseLabel: L("收起日志"),
            toggle: {
                logOpen.toggle()
                PhoneUseLocation.logOpen = logOpen
            }
        ) {
            logBody
        } collapsed: {
            Text(desk.runs.isEmpty ? L("还没有执行记录。") : L("共 %lld 条日志", desk.runs.count))
                .font(.system(size: 12))
                .textSecondaryStyle()
        }
    }

    private var logBody: some View {
        let shown = displayedRuns
        return VStack(alignment: .leading, spacing: 8) {
            if shown.isEmpty {
                Text(L("还没有执行记录。"))
                    .font(.system(size: 13))
                    .textSecondaryStyle()
            }
            ForEach(shown) { run in
                runRow(run)
            }
            if desk.runs.count > 8 {
                Button(showAll ? L("收起") : L("全部日志")) { showAll.toggle() }
                    .buttonStyle(FieldMenuStyle())
            }
        }
    }

    private func runRow(_ run: PhoneRun) -> some View {
        let open = openedRun == run.id
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                openedRun = open ? nil : run.id
            } label: {
                HStack(spacing: 8) {
                    resultMark(run.result)
                    Text(stamp(run.started))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                    Text(run.lines.last?.message ?? "")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(PlainPressStyle())
            if open {
                Text(run.lines.map { stamp($0.date) + " " + $0.message }.joined(separator: "\n"))
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(reduceMotion ? nil : Motion.enter, value: open)
    }

    private func resultMark(_ result: PhoneRunResult) -> some View {
        Text(resultTitle(result))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(result == .success ? palette.accentInk : palette.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(result == .success ? palette.accentSoft : palette.field, in: Capsule())
    }

    private var displayedRuns: [PhoneRun] {
        let ordered = desk.runs.reversed()
        return showAll ? Array(ordered) : Array(ordered.prefix(8))
    }

    private var overlapWarning: Bool {
        guard let draft = currentDraft() else { return false }
        return PhoneTasks.overlaps(draft, tasks: desk.tasks)
    }

    private func matched(_ task: PhoneTaskSnapshot) -> PhoneRun? {
        guard task.kind != .command else { return nil }
        return PhoneTasks.matchedRun(kind: task.kind, runs: desk.runs, since: startedAt[task.id])
    }

    private func commandLog(_ task: PhoneTaskSnapshot) -> String {
        guard task.owned, task.kind == .command, let label = PhoneTasks.ownedLabel(task.id) else { return "" }
        let url = PhoneUseLocation.state.appendingPathComponent("logs/\(label).log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(8).joined(separator: "\n")
    }

    private func currentDraft() -> PhoneTaskDraft? {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: clock)
        guard let hour = parts.hour, let minute = parts.minute else { return nil }
        return PhoneTaskDraft(title: title, note: note, kind: kind, command: command, weekdays: weekdays, hour: hour, minute: minute)
    }

    private func reload() {
        if case .ready(let url) = PhoneUseLocation.resolveCheckout(checkoutText) {
            let sync = PhoneTasks.syncTaskFiles(
                checkout: url,
                state: PhoneUseLocation.state,
                agents: PhoneUseLocation.agents,
                saved: PhoneUseLocation.saved,
                launch: SystemPhoneTaskLaunch()
            )
            if !sync.summary.isEmpty { message = sync.summary }
        }
        desk = PhoneTasks.desk(launch: SystemPhoneTaskLaunch())
        stage = PhoneStage.load(directory: PhoneUseLocation.state)
    }

    private func saveCheckout() {
        switch PhoneUseLocation.resolveCheckout(checkoutText) {
        case .ready(let url):
            PhoneUseLocation.setCheckout(url)
            checkoutText = url.path
            message = L("脚本位置已保存。")
            reload()
        case .missingScript:
            message = L("这个目录里没有 scripts/punch.py。")
        case .notDirectory:
            message = L("脚本位置要是一个文件夹。")
        }
    }

    private func hostPicker(_ selection: Binding<PhoneAIHost>) -> some View {
        Picker(L("发给"), selection: selection) {
            ForEach(PhoneAIHost.allCases) { host in
                Text(host.title).tag(host)
            }
        }
        .pickerStyle(.menu)
    }

    private func promptCard(_ text: String, host: PhoneAIHost, copy: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack(spacing: 8) {
                Button(L("复制这段提示词"), action: copy)
                    .buttonStyle(FieldMenuStyle())
                if let bundle = host.bundleIdentifier {
                    Button(L("打开 %@", host.title)) {
                        openAI(bundle, missing: L("没有找到 %@。提示词可以贴到它的聊天里。", host.title))
                    }
                    .buttonStyle(FieldMenuStyle())
                }
            }
        }
    }

    private var displayedTaskPrompt: String? {
        liveTaskPrompt ?? (keptTaskPrompt.isEmpty ? nil : keptTaskPrompt)
    }

    private var liveTaskPrompt: String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let draft = currentDraft(), !draft.weekdays.isEmpty else { return nil }
        let action = PhoneTaskBrief.action(kind: draft.kind, note: detail)
        guard !action.isEmpty else { return nil }
        let rootPath: String
        switch PhoneUseLocation.resolveCheckout(checkoutText) {
        case .ready(let url):
            rootPath = url.path
        case .missingScript, .notDirectory:
            rootPath = L("还没有设置脚本位置。先保存含有 scripts/punch.py 的项目目录。")
        }
        return PhoneTaskBrief.taskPrompt(
            host: taskHost,
            title: name,
            note: action,
            schedule: PhoneTasks.scheduleText(draft.slots),
            rootPath: rootPath,
            slug: PhoneTaskBrief.slug(title: name),
            kind: draft.kind,
            weekdays: draft.slots.map(\.weekday),
            hour: draft.hour,
            minute: draft.minute
        )
    }

    private func copyTaskPrompt(_ prompt: String) {
        keptTaskPrompt = prompt
        LocalPasteboard.copy(prompt)
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft = currentDraft(), !name.isEmpty, !draft.weekdays.isEmpty else {
            message = L("提示词已复制。贴到 %@ 的聊天里。", taskHost.title)
            return
        }
        let action = PhoneTaskBrief.action(kind: draft.kind, note: detail)
        guard !action.isEmpty else {
            message = L("先写下这个定时要做什么。")
            return
        }
        switch PhoneUseLocation.resolveCheckout(checkoutText) {
        case .ready(let url):
            do {
                let written = try PhoneTaskBrief.write(
                    title: name,
                    note: action,
                    schedule: PhoneTasks.scheduleText(draft.slots),
                    checkout: url,
                    host: taskHost,
                    kind: draft.kind,
                    weekdays: draft.slots.map(\.weekday),
                    hour: draft.hour,
                    minute: draft.minute
                )
                var text = L("提示词已复制。贴到 %@ 的聊天里。文件在 scripts/tasks/%@.md。", taskHost.title, written.slug)
                if written.scriptExists {
                    text += " " + L("旁边已经有同名脚本，让 AI 先看再决定要不要覆盖。")
                }
                message = text
            } catch let error as ToolError {
                message = error.text
            } catch {
                message = error.localizedDescription
            }
        case .missingScript:
            message = L("提示词已复制。这个目录里没有 scripts/punch.py，文件还没写入。")
        case .notDirectory:
            message = L("提示词已复制。先设置脚本位置，文件还没写入。")
        }
    }

    private func openAI(_ bundle: String, missing: String) {
        if PhoneTaskBrief.open(bundle) { return }
        message = missing
    }

    private func toggle(_ task: PhoneTaskSnapshot) {
        do {
            try PhoneTasks.setEnabled(id: task.id, enabled: !task.enabled, checkout: PhoneUseLocation.checkout, state: PhoneUseLocation.state, agents: PhoneUseLocation.agents, saved: PhoneUseLocation.saved, launch: SystemPhoneTaskLaunch())
            message = ""
            reload()
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
    }

    private func delete(_ task: PhoneTaskSnapshot) {
        pendingDelete = nil
        if let source = task.source, PhoneTaskFile.isTaskName(source), let root = PhoneUseLocation.savedCheckout {
            let file = root
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("tasks", isDirectory: true)
                .appendingPathComponent(source)
            try? FileManager.default.removeItem(at: file)
        }
        do {
            try PhoneTasks.remove(id: task.id, agents: PhoneUseLocation.agents, saved: PhoneUseLocation.saved, launch: SystemPhoneTaskLaunch())
            reload()
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
    }

    private func attach(_ task: PhoneTaskSnapshot) {
        do {
            try PhoneTasks.attachBuiltin(label: task.id, agents: PhoneUseLocation.agents, launch: SystemPhoneTaskLaunch())
            reload()
        } catch let error as ToolError {
            message = error.text
        } catch {
            message = error.localizedDescription
        }
    }

    private func installDefaults(_ task: PhoneTaskSnapshot) {
        let python = ShellLiteral.singleQuoted(PhoneTasks.pythonExecutable(agents: PhoneUseLocation.agents))
        let script = ShellLiteral.singleQuoted(PhoneUseLocation.script.path)
        runShell("\(python) \(script) install", taskID: task.id, readPunchLog: false)
    }

    private func start(_ task: PhoneTaskSnapshot) {
        pendingRun = nil
        confirmRun = false
        switch task.kind {
        case .command:
            if let gap = PhoneTaskBrief.missingScript(command: task.command, checkout: PhoneUseLocation.checkout) {
                let text = L("脚本还没有写到 %@。", gap)
                message = text
                reports[task.id] = text
                return
            }
            runShell(PhoneTasks.commandShell(command: task.command, checkout: PhoneUseLocation.checkout), taskID: task.id, readPunchLog: false)
        case .punchIn, .punchOut:
            guard desk.scriptReady else {
                message = L("没有找到打卡脚本。")
                reports[task.id] = L("没有找到打卡脚本。")
                return
            }
            let kind = task.kind == .punchOut ? "out" : "in"
            let python = ShellLiteral.singleQuoted(PhoneTasks.pythonExecutable(agents: PhoneUseLocation.agents))
            let script = ShellLiteral.singleQuoted(PhoneUseLocation.script.path)
            runShell("\(python) \(script) \(kind) --now", taskID: task.id, readPunchLog: true)
        }
    }

    private func runShell(_ command: String, taskID: String, readPunchLog: Bool) {
        let started = Date()
        busy = true
        runningID = taskID
        startedAt[taskID] = started
        live = L("正在执行")
        reports[taskID] = L("正在执行")
        Task {
            let result = await Shell.run(command, timeout: 180)
            var parts = [result.stdout, result.stderr].filter { !$0.isEmpty }
            if readPunchLog, let text = try? String(contentsOf: PhoneUseLocation.punchLog, encoding: .utf8) {
                let excerpt = PhoneLog.excerpt(after: started, in: text)
                if !excerpt.isEmpty { parts.append(excerpt) }
            }
            let text = parts.joined(separator: "\n")
            let shown = text.isEmpty ? L("没有输出。") : text
            live = shown
            reports[taskID] = shown
            busy = false
            runningID = nil
            reload()
        }
    }

    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private func dayMark(_ weekday: Int) -> String {
        if AppLanguage.current == .english {
            switch weekday {
            case 1: return "Mo"
            case 2: return "Tu"
            case 3: return "We"
            case 4: return "Th"
            case 5: return "Fr"
            case 6: return "Sa"
            default: return "Su"
            }
        }
        return String(PhoneTasks.weekdayName(weekday).suffix(1))
    }

    private func resultTitle(_ result: PhoneRunResult) -> String {
        switch result {
        case .success: L("成功")
        case .unconfirmed: L("未确认")
        case .skipped: L("跳过")
        case .stopped: L("已停止")
        case .open: L("未结束")
        case .note: L("记录")
        }
    }
}

private struct PhoneWeekdayPicker: View {
    @Binding var weekdays: Set<Int>
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PhoneSlot.weekOrder, id: \.self) { weekday in
                let on = weekdays.contains(weekday)
                Button {
                    if weekdays.contains(weekday) {
                        weekdays.remove(weekday)
                    } else {
                        weekdays.insert(weekday)
                    }
                } label: {
                    Text(PhoneTasks.weekdayName(weekday))
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(on ? palette.accentInk : palette.textSecondary)
                        .background(on ? palette.accentSoft : palette.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(on ? L("取消%@", PhoneTasks.weekdayName(weekday)) : PhoneTasks.weekdayName(weekday))
            }
        }
    }
}

private enum PhoneTaskTabMotion {
    static let pill = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.26)
    static let hover = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
}

private struct PhoneTaskTabFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct PhoneTaskTabStrip: View {
    var tasks: [PhoneTaskSnapshot]
    var selection: String?
    var reduceMotion: Bool
    var choose: (String) -> Void
    @Environment(\.palette) private var palette
    @State private var frames: [String: CGRect] = [:]
    @State private var pillReady = false
    @State private var hovered: String?
    @FocusState private var focused: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                strip
            }
            .scrollIndicators(.hidden)
            .onChange(of: selection) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    withAnimation(PhoneTaskTabMotion.pill) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("定时"))
    }

    private var strip: some View {
        ZStack(alignment: .topLeading) {
            if let selection, let frame = frames[selection] {
                Capsule(style: .continuous)
                    .fill(palette.surface)
                    .overlay(Capsule(style: .continuous).stroke(palette.line))
                    .frame(width: frame.width, height: frame.height)
                    .shadow(color: .black.opacity(0.06), radius: 1.5, y: 1)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.identity)
                    .animation(pillReady && !reduceMotion ? PhoneTaskTabMotion.pill : nil, value: selection)
            }
            HStack(spacing: 0) {
                ForEach(tasks) { task in
                    tabButton(task)
                }
            }
        }
        .coordinateSpace(name: "phoneTaskTabs")
        .onPreferenceChange(PhoneTaskTabFrameKey.self) { frames in
            self.frames = frames
            if !pillReady, let selection, frames[selection] != nil {
                pillReady = true
            }
        }
        .padding(4)
        .background(palette.field, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(palette.line))
    }

    private func tabButton(_ task: PhoneTaskSnapshot) -> some View {
        let selected = selection == task.id
        let hot = selected || hovered == task.id
        return Button {
            choose(task.id)
        } label: {
            Text(task.title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(hot ? palette.ink : palette.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minWidth: 88, minHeight: 32)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: PhoneTaskTabFrameKey.self,
                    value: [task.id: geo.frame(in: .named("phoneTaskTabs"))]
                )
            }
        }
        .id(task.id)
        .focused($focused, equals: task.id)
        .onHover { inside in
            hovered = inside ? task.id : (hovered == task.id ? nil : hovered)
        }
        .animation(reduceMotion ? nil : PhoneTaskTabMotion.hover, value: hot)
        .onKeyPress(.leftArrow) {
            step(from: task.id, by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            step(from: task.id, by: 1)
            return .handled
        }
        .accessibilityLabel(task.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? L("已选") : L("未选"))
    }

    private func step(from id: String, by delta: Int) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let next = tasks[(index + delta + tasks.count) % tasks.count]
        focused = next.id
        choose(next.id)
    }
}
