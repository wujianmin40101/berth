import AppKit
import SwiftUI

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
                Text(message).font(.system(size: 12)).textSecondaryStyle()
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 12) {
                    Text(report?.summary ?? L("正在读取内存。"))
                        .font(.system(size: 13))
                        .textSecondaryStyle()
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
                        .textSecondaryStyle()
                }
            }
            WorkspacePanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("占资源的进程"))
                        .font(.system(size: 13, weight: .semibold))
                    if hogs.isEmpty {
                        Text(L("现在没有明显占着 CPU 或内存的进程。"))
                            .font(.system(size: 13))
                            .textSecondaryStyle()
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
                                    .textSecondaryStyle()
                            }
                            Spacer()
                            if hog.canStop {
                                Button(L("结束")) { pending = hog }
                                    .buttonStyle(FieldMenuStyle())
                            } else {
                                Text(L("不能结束这个进程。"))
                                    .font(.system(size: 12))
                                    .textSecondaryStyle()
                            }
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
                        .textSecondaryStyle()
                    if items.isEmpty {
                        Text(L("没有用户启动代理。"))
                            .font(.system(size: 13))
                            .textSecondaryStyle()
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
        guard hog.canStop else {
            message = L("不能结束这个进程。")
            return
        }
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
