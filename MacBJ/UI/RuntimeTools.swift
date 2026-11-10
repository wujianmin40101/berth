import SwiftUI

struct PortsTool: View {
    var ownedPIDs: Set<Int32>
    @State private var rows: [PortUse] = []
    @State private var message = ""
    @State private var loading = false
    @State private var pending: PortUse?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("端口"),
                subtitle: L("相当于 lsof 的图形界面。结束进程前会再确认一次。"),
                help: FeatureHelp.ports,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading
            ) {
                Task { await reload() }
            }
            if !message.isEmpty {
                Text(message)
                    .font(.system(size: 12))
                    .textSecondaryStyle()
            }
            if rows.isEmpty, !loading {
                Text(message.isEmpty ? L("没有正在监听的 TCP 端口。") : " ")
                    .font(.system(size: 13))
                    .textSecondaryStyle()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        portRow(row)
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("结束占用这个端口的进程"), isPresented: pendingBinding, titleVisibility: .visible) {
            Button(L("结束"), role: .destructive) { signal(force: false) }
            Button(L("强制结束"), role: .destructive) { signal(force: true) }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(pending.map { "\($0.command) · \($0.address) · PID \($0.pid)" } ?? "")
        }
        .task { await reload() }
    }

    private func portRow(_ row: PortUse) -> some View {
        HStack(spacing: 12) {
            Text(":\(row.port)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.command)
                        .font(.system(size: 13, weight: .medium))
                    if ownedPIDs.contains(row.pid) {
                        Text(L("本地服务"))
                            .font(.system(size: 11, weight: .semibold))
                            .textSecondaryStyle()
                    }
                }
                Text("PID \(row.pid) · \(row.address)")
                    .font(.system(size: 11))
                    .textSecondaryStyle()
            }
            Spacer()
            Button(L("结束")) { pending = row }
                .buttonStyle(FieldMenuStyle())
        }
        .padding(.vertical, 8)
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func reload() async {
        loading = true
        let result = await PortListing.load()
        loading = false
        switch result {
        case .success(let found):
            rows = found
            message = ""
        case .failure(let failure):
            message = failure.text
        }
    }

    private func signal(force: Bool) {
        guard let target = pending else { return }
        pending = nil
        Task {
            message = await ProcessSignal.send(pid: target.pid, force: force) ?? L("已发送结束信号。")
            await reload()
        }
    }
}

struct ProcessesTool: View {
    var ownedPIDs: Set<Int32>
    @State private var rows: [RuntimeProcess] = []
    @State private var message = ""
    @State private var loading = false
    @State private var pending: RuntimeProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(
                title: L("进程"),
                subtitle: L("只列出 Node 和 Python。本工具启动的服务会标出来。"),
                help: FeatureHelp.processes,
                actionTitle: L("刷新"),
                actionIcon: "arrow.clockwise",
                actionDisabled: loading
            ) {
                Task { await reload() }
            }
            if !message.isEmpty {
                Text(message).font(.system(size: 12)).textSecondaryStyle()
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(row.memoryMB) MB")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(width: 72, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("PID \(row.pid)")
                                        .font(.system(size: 13, weight: .medium))
                                    if ownedPIDs.contains(row.pid) {
                                        Text(L("本地服务"))
                                            .font(.system(size: 11, weight: .semibold))
                                            .textSecondaryStyle()
                                    }
                                }
                                Text(row.command)
                                    .font(.system(size: 11, design: .monospaced))
                                    .textSecondaryStyle()
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            Button(L("结束")) { pending = row }
                                .buttonStyle(FieldMenuStyle())
                        }
                        .padding(.vertical, 8)
                        Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                    }
                }
            }
            if rows.isEmpty, !loading {
                Text(L("现在没有 Node 或 Python 进程。"))
                    .font(.system(size: 13))
                    .textSecondaryStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(L("结束这个进程"), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button(L("结束"), role: .destructive) { signal(force: false) }
            Button(L("强制结束"), role: .destructive) { signal(force: true) }
            Button(L("取消"), role: .cancel) {}
        } message: {
            Text(pending.map { "PID \($0.pid) · \($0.command)" } ?? "")
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        let result = await ProcessListing.load()
        loading = false
        switch result {
        case .success(let found):
            rows = found
            message = ""
        case .failure(let failure):
            message = failure.text
        }
    }

    private func signal(force: Bool) {
        guard let target = pending else { return }
        pending = nil
        Task {
            message = await ProcessSignal.send(pid: target.pid, force: force) ?? L("已发送结束信号。")
            await reload()
        }
    }
}

struct ServicesTool: View {
    var model: ToolboxModel
    var projectDirectory: URL?
    @State private var name = ""
    @State private var directory = ""
    @State private var command = ""
    @State private var injectSecrets = true
    @State private var message = ""
    @State private var expanded: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: L("本地服务"), subtitle: L("在这里启动的开发服务会留在进程列表里。退出%@时它们会一起停。", ProductName.title), help: FeatureHelp.services)
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        ToolTextField(title: L("名称"), text: $name)
                        ToolTextField(title: L("目录"), text: $directory)
                        ToolTextField(title: L("命令"), text: $command)
                        Toggle(L("启动时注入钥匙串里的变量"), isOn: $injectSecrets)
                            .font(.system(size: 12))
                        HStack {
                            if projectDirectory != nil {
                                Button(L("填入当前项目")) {
                                    directory = projectDirectory?.path ?? ""
                                }
                                .buttonStyle(FieldMenuStyle())
                            }
                            Spacer()
                            Button(L("添加")) { add() }
                                .buttonStyle(TintCapsuleStyle())
                        }
                        if !command.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text(L("将执行 %@", command))
                                .font(.system(size: 12, design: .monospaced))
                                .textSecondaryStyle()
                                .textSelection(.enabled)
                        }
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).textSecondaryStyle()
                }
                ForEach(model.services) { service in
                    serviceCard(service)
                }
            }
        }
    }

    private func serviceCard(_ service: DevService) -> some View {
        let active = model.running.contains(service.id)
        return WorkspacePanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(service.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(service.command)
                            .font(.system(size: 12, design: .monospaced))
                            .textSecondaryStyle()
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(active ? L("运行中") : L("已停止"))
                        .font(.system(size: 12, weight: .medium))
                        .textSecondaryStyle()
                }
                Text(service.directory)
                    .font(.system(size: 11))
                    .textSecondaryStyle()
                    .lineLimit(1)
                HStack {
                    Button(active ? L("停止") : L("启动")) {
                        if active {
                            model.stop(service, force: false)
                        } else if let failure = model.start(service) {
                            message = failure
                        }
                    }
                    .buttonStyle(TintCapsuleStyle())
                    if active {
                        Button(L("强制停止")) { model.stop(service, force: true) }
                            .buttonStyle(FieldMenuStyle())
                    }
                    Button(expanded == service.id ? L("收起日志") : L("日志")) {
                        expanded = expanded == service.id ? nil : service.id
                    }
                    .buttonStyle(FieldMenuStyle())
                    Spacer()
                    Button(L("删除")) { model.removeService(service) }
                        .buttonStyle(FieldMenuStyle())
                        .disabled(active)
                }
                if expanded == service.id {
                    Text(model.logs[service.id, default: L("还没有输出。")])
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func add() {
        message = model.addService(name: name, directory: directory, command: command, injectSecrets: injectSecrets) ?? ""
        if message.isEmpty {
            name = ""
            command = ""
        }
    }
}
