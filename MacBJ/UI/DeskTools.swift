import SwiftUI

struct HostsTool: View {
    var model: ToolboxModel
    @State private var bodyText = ""
    @State private var profileName = ""
    @State private var message = ""
    @State private var writing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Hosts", subtitle: L("这里没有预置的测试或线上地址。保存时会先备份，再请系统确认。"), help: FeatureHelp.hosts)
                TextEditor(text: $bodyText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Button(L("重新读取")) { load() }
                        .buttonStyle(FieldMenuStyle())
                    Button(writing ? L("正在写入") : L("校验并写入")) { write() }
                        .buttonStyle(TintCapsuleStyle())
                        .disabled(writing)
                    Spacer()
                }
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("我的解析方案"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(L("方案只存在这台电脑上，内容是你自己保存的。"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        ToolTextField(title: L("方案名称"), text: $profileName)
                        Button(L("保存当前内容为方案")) { saveProfile() }
                            .buttonStyle(FieldMenuStyle())
                        ForEach(model.hostsProfiles) { profile in
                            HStack {
                                Text(profile.name)
                                    .font(.system(size: 13))
                                Spacer()
                                Button(L("载入")) { bodyText = profile.body }
                                    .buttonStyle(FieldMenuStyle())
                                Button(L("删除")) { model.removeHostsProfile(profile) }
                                    .buttonStyle(FieldMenuStyle())
                            }
                        }
                    }
                }
            }
        }
        .task { load() }
    }

    private func load() {
        switch HostsFile.read() {
        case .success(let text):
            bodyText = text
            message = ""
        case .failure(let failure):
            message = failure.text
        }
    }

    private func write() {
        if let problem = HostsFile.problem(in: bodyText) {
            message = problem
            return
        }
        HostsFile.backup(bodyText)
        writing = true
        let text = bodyText
        Task {
            message = await HostsFile.install(text) ?? L("已经写入 /etc/hosts。旧文件备份在 /etc/hosts.macbj-bak。")
            writing = false
        }
    }

    private func saveProfile() {
        message = model.addHostsProfile(name: profileName, body: bodyText) ?? L("已保存这份解析。")
        if message == L("已保存这份解析。") { profileName = "" }
    }
}

struct SecretsTool: View {
    @State private var names: [String] = []
    @State private var name = ""
    @State private var value = ""
    @State private var revealed = ""
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: L("密钥"), subtitle: L("值存在系统钥匙串里。复制出来的是 export 命令，不会改 ~/.zshrc。"), help: FeatureHelp.secrets)
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        ToolTextField(title: L("变量名"), text: $name)
                        ToolTextField(title: L("值"), text: $value)
                        Button(L("保存到钥匙串")) { save() }
                            .buttonStyle(TintCapsuleStyle())
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(names, id: \.self) { item in
                    HStack {
                        Text(item)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Text(revealed == item ? (SecretStore.value(named: item) ?? "—") : "••••••")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button(revealed == item ? L("隐藏") : L("显示")) {
                            revealed = revealed == item ? "" : item
                        }
                        .buttonStyle(FieldMenuStyle())
                        Button(L("复制")) { copyExport(item) }
                            .buttonStyle(FieldMenuStyle())
                        Button(L("删除")) {
                            SecretStore.remove(name: item)
                            reload()
                        }
                        .buttonStyle(FieldMenuStyle())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .task { reload() }
    }

    private func reload() {
        names = SecretStore.names()
    }

    private func save() {
        message = SecretStore.save(name: name.trimmingCharacters(in: .whitespaces), value: value) ?? L("已放进钥匙串。")
        if message == L("已放进钥匙串。") {
            name = ""
            value = ""
            reload()
        }
    }

    private func copyExport(_ item: String) {
        guard let secret = SecretStore.value(named: item) else { return }
        LocalPasteboard.copy("export \(item)=\(ShellQuote.singleQuoted(secret))")
        message = L("已复制 %@ 的 export 命令。", item)
    }
}

struct GitTool: View {
    @State private var name = ""
    @State private var email = ""
    @State private var proxy = ""
    @State private var aliases: [String] = []
    @State private var publicKey = ""
    @State private var aliasName = ""
    @State private var aliasCommand = ""
    @State private var message = ""
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: "Git", subtitle: L("改的是全局 gitconfig。已有的 SSH 公钥不会被覆盖。"), help: FeatureHelp.git)
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        ToolTextField(title: L("用户名"), text: $name)
                        ToolTextField(title: L("邮箱"), text: $email)
                        ToolTextField(title: L("http.proxy，可留空"), text: $proxy)
                        Button(L("保存全局配置")) { save() }
                            .buttonStyle(TintCapsuleStyle())
                            .disabled(!loaded)
                    }
                }
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("别名"))
                            .font(.system(size: 13, weight: .semibold))
                        ForEach(aliases, id: \.self) { alias in
                            Text(alias)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        ToolTextField(title: L("别名"), text: $aliasName)
                        ToolTextField(title: L("命令"), text: $aliasCommand)
                        Button(L("添加别名")) { addAlias() }
                            .buttonStyle(FieldMenuStyle())
                    }
                }
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("SSH 公钥"))
                            .font(.system(size: 13, weight: .semibold))
                        Text(publicKey.isEmpty ? L("还没有 ~/.ssh/id_ed25519.pub。") : publicKey)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                        HStack {
                            Button(L("生成 ed25519")) { generate() }
                                .buttonStyle(TintCapsuleStyle())
                                .disabled(!publicKey.isEmpty)
                            Button(L("复制公钥")) { LocalPasteboard.copy(publicKey) }
                                .buttonStyle(FieldMenuStyle())
                                .disabled(publicKey.isEmpty)
                        }
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        let snapshot = await GitWorkbench.load()
        name = snapshot.name
        email = snapshot.email
        proxy = snapshot.proxy
        aliases = snapshot.aliases
        publicKey = snapshot.publicKey
        loaded = true
    }

    private func save() {
        Task {
            message = await GitWorkbench.save(name: name, email: email, proxy: proxy) ?? L("已写入全局 Git 配置。")
            await reload()
        }
    }

    private func addAlias() {
        Task {
            message = await GitWorkbench.addAlias(name: aliasName, command: aliasCommand) ?? L("已添加别名。")
            aliasName = ""
            aliasCommand = ""
            await reload()
        }
    }

    private func generate() {
        Task {
            message = await GitWorkbench.generateKey() ?? L("已生成公钥。")
            await reload()
        }
    }
}

struct ProxyTool: View {
    var model: ToolboxModel
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: L("代理"), subtitle: L("地址完全由你填写。这里不会提供节点，也不会改 shell 配置。"), help: FeatureHelp.proxy)
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        ToolTextField(title: "http_proxy", text: Bindable(model).proxyHTTP)
                        ToolTextField(title: "https_proxy", text: Bindable(model).proxyHTTPS)
                        ToolTextField(title: "ALL_PROXY", text: Bindable(model).proxyAll)
                        ToolTextField(title: "NO_PROXY", text: Bindable(model).proxyBypass)
                        Toggle(L("本地服务启动时带上这些变量"), isOn: Bindable(model).proxyForServices)
                            .font(.system(size: 12))
                        HStack {
                            Button(L("保存")) {
                                if let problem = model.saveProxy() {
                                    message = problem
                                } else {
                                    message = L("已保存在本机。")
                                }
                            }
                            .buttonStyle(TintCapsuleStyle())
                            Button(L("复制 export")) { copy() }
                                .buttonStyle(FieldMenuStyle())
                        }
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func copy() {
        switch model.proxyCommand() {
        case .success(let command):
            LocalPasteboard.copy(command)
            message = L("已复制。粘贴到终端后才会生效。")
        case .failure(let failure):
            message = failure.text
        }
    }
}

struct SnippetsTool: View {
    var model: ToolboxModel
    @State private var title = ""
    @State private var command = ""
    @State private var output = ""
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: L("命令收藏"), subtitle: L("命令留在本机。运行时会用你的登录 shell，输出显示在下面。"), help: FeatureHelp.snippets)
                WorkspacePanel {
                    VStack(alignment: .leading, spacing: 10) {
                        ToolTextField(title: L("名称"), text: $title)
                        ToolTextField(title: L("命令"), text: $command)
                        Button(L("收藏")) { add() }
                            .buttonStyle(TintCapsuleStyle())
                    }
                }
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(model.snippets) { snippet in
                    WorkspacePanel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(snippet.title)
                                .font(.system(size: 14, weight: .semibold))
                            Text(snippet.command)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                            HStack {
                                Button(L("复制")) { LocalPasteboard.copy(snippet.command) }
                                    .buttonStyle(FieldMenuStyle())
                                Button(L("运行")) { run(snippet) }
                                    .buttonStyle(TintCapsuleStyle())
                                Spacer()
                                Button(L("删除")) { model.removeSnippet(snippet) }
                                    .buttonStyle(FieldMenuStyle())
                            }
                        }
                    }
                }
                if !output.isEmpty {
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func add() {
        message = model.addSnippet(title: title, command: command) ?? ""
        if message.isEmpty {
            title = ""
            command = ""
        }
    }

    private func run(_ snippet: CommandSnippet) {
        output = L("正在执行\n%@\n", snippet.command)
        Task {
            let result = await Shell.run(snippet.command, timeout: 40)
            let text = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            output = L("正在执行\n%@\n\n", snippet.command) + (text.isEmpty ? L("没有输出。") : text)
        }
    }
}

struct UtilitiesTool: View {
    var model: ToolboxModel
    @State private var input = ""
    @State private var output = ""
    @State private var message = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PageHeader(title: L("格式工具"), subtitle: L("JSON、时间戳、Base64 和 URL。剪贴板只在你点按钮时读取。"), help: FeatureHelp.utilities)
                TextEditor(text: $input)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                actionRow
                if !message.isEmpty {
                    Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if !output.isEmpty {
                    Text(output)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    Button(L("复制结果")) { LocalPasteboard.copy(output) }
                        .buttonStyle(FieldMenuStyle())
                }
                if !model.clipboardPins.isEmpty {
                    Text(L("手动保留的剪贴板"))
                        .font(.system(size: 13, weight: .semibold))
                    ForEach(model.clipboardPins, id: \.self) { pin in
                        HStack(alignment: .top) {
                            Text(pin)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Spacer()
                            Button(L("用它")) { input = pin }
                                .buttonStyle(FieldMenuStyle())
                            Button(L("删除")) { model.removeClipboardPin(pin) }
                                .buttonStyle(FieldMenuStyle())
                        }
                    }
                }
            }
        }
    }

    private var actionRow: some View {
        let actions: [(String, () -> Void)] = [
            (L("美化 JSON"), { transform { DevTransforms.formatJSON($0, pretty: true) } }),
            (L("压缩 JSON"), { transform { DevTransforms.formatJSON($0, pretty: false) } }),
            (L("时间戳"), { transform { DevTransforms.timestamp($0) } }),
            (L("Base64 编码"), { output = DevTransforms.base64Encode(input); message = "" }),
            (L("Base64 解码"), { transform(DevTransforms.base64Decode) }),
            (L("URL 编码"), { output = DevTransforms.urlEncode(input); message = "" }),
            (L("URL 解码"), { transform(DevTransforms.urlDecode) }),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(L("读剪贴板")) {
                    input = LocalPasteboard.string() ?? ""
                    message = input.isEmpty ? L("剪贴板里没有文本。") : ""
                }
                .buttonStyle(FieldMenuStyle())
                Button(L("保留剪贴板")) {
                    guard let text = LocalPasteboard.string(), !text.isEmpty else {
                        message = L("剪贴板里没有文本。")
                        return
                    }
                    model.pinClipboard(text)
                    message = L("已保留。")
                }
                .buttonStyle(FieldMenuStyle())
                Button(L("现在的时间戳")) {
                    input = String(Int(Date().timeIntervalSince1970))
                    transform { DevTransforms.timestamp($0) }
                }
                .buttonStyle(FieldMenuStyle())
            }
            FlexibleActions(actions: actions)
        }
    }

    private func transform(_ work: (String) -> Result<String, ToolError>) {
        switch work(input) {
        case .success(let text):
            output = text
            message = ""
        case .failure(let failure):
            message = failure.text
        }
    }
}

private struct FlexibleActions: View {
    var actions: [(String, () -> Void)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button(action.0, action: action.1)
                    .buttonStyle(FieldMenuStyle())
            }
        }
    }
}
