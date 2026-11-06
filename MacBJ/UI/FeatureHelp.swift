import SwiftUI

enum FeatureHelp {
    static let ports = """
    刷新后读取本机正在监听的 TCP 端口，来源是 lsof。列表里能看到端口、进程名、PID 和地址。
    点「结束」会先确认。结束发送正常退出信号，强制结束会立即终止。不会结束泊位自己。从这里启动的本地服务会标出来。
    """

    static let processes = """
    只列出命令里能认出的 Node 和 Python，并按驻留内存估算占用。其他程序不会出现在这里。
    结束前会确认，并连同它拉起的子进程一起结束。强制结束会立即终止。
    """

    static let services = """
    添加时要填写名称、已经存在的目录和启动命令。启动后用登录 shell 在那个目录里执行，输出显示在日志里。
    停止会结束这个进程和它的子进程。可以在启动时注入钥匙串里的变量，以及你保存的代理。退出泊位时，会强制结束这里启动的服务和它拉起的子进程。
    """

    static let hosts = """
    打开时读取这台电脑的 /etc/hosts。写入前会检查每一行的地址和主机名，并且必须保留 localhost。
    「校验并写入」会先在本机留一份备份，再弹出系统密码框。取消密码框不会改文件。下面的方案只存在这台电脑上，载入后才进入编辑区，不会自动写进 hosts。
    """

    static let secrets = """
    变量名和值保存在系统钥匙串里，不会写入 ~/.zshrc。点「显示」可以看原文，点「复制」得到一行 export 命令。
    钥匙串拒绝保存时，页面会写出原因，不会显示成已经保存。
    """

    static let git = """
    保存的是 Git 全局配置里的用户名、邮箱和 http.proxy。某一项留空再保存，会去掉对应的全局设置。
    别名写入全局 gitconfig。生成公钥只在还没有 ~/.ssh/id_ed25519.pub 时进行，不会覆盖已经存在的钥匙。
    """

    static let proxy = """
    地址由你填写，保存在本机。这里不提供节点，也不修改 shell 配置或系统网络代理。
    「复制 export」得到的命令，粘贴到终端后才在那个终端里生效。勾选后，本地服务启动时只会带上填了、并且合法的变量，空着的项不会覆盖服务自己的代理。
    """

    static let snippets = """
    名称和命令保存在这台电脑上。点「运行」会用登录 shell 执行，标准输出和错误输出显示在下面。命令超时后会被结束。
    """

    static let utilities = """
    美化或压缩 JSON，把 Unix 时间戳换成日期，以及 Base64、URL 的编码和解码，都在本机计算，不会上传。
    剪贴板只在点「读剪贴板」时读取。结果可以复制。
    """

    static let memory = """
    按活动监视器的口径分成应用内存、联动内存、已压缩、缓存文件和可用。条形图和环形图是同一份数据，悬停能看到对应的一块。
    下面列出占内存较多的应用，带有图标和 CPU。退出前会确认。系统进程和泊位不能从这里退出。
    """

    static let uninstall = """
    只处理「应用程序」或用户应用程序目录里直接放着的应用。卸载会把它移到废纸篓，并带走用户资源库里只属于它的偏好、缓存和支持文件。和别的应用共用的文件会留下。
    系统应用和泊位不能卸载。上次使用时间来自本机记录，没有记录会直接写明。
    """

    static let caches = """
    只统计可以重新生成的缓存、日志和废纸篓。个人文件不在这个列表里。
    清理前会确认。删掉的是对应目录里的内容，下次用到时会重新生成。
    """

    static let disk = """
    按目录统计实际占用，矩形面积越大，占用越多。点一块可以进入下一级，用面包屑或 Esc 返回。
    各项加起来不一定等于磁盘已用空间，系统快照不在这些目录里。没有完全磁盘访问权限时，受保护的目录会统计得偏小。
    """

    static let speed = """
    「释放内存」和「刷新 DNS」会弹出系统密码框。取消后不会改任何东西。
    结束进程前会确认，不会结束系统关键进程和泊位。启动代理只开关当前用户目录里的 LaunchAgents。
    """
}

private struct FeatureHelpKey: EnvironmentKey {
    static let defaultValue: ((String, String) -> Void)? = nil
}

extension EnvironmentValues {
    var presentFeatureHelp: ((String, String) -> Void)? {
        get { self[FeatureHelpKey.self] }
        set { self[FeatureHelpKey.self] = newValue }
    }
}

struct FeatureHelpHost<Content: View>: View {
    var reset: String = ""
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mounted = false
    @State private var visible = false
    @State private var closing = false
    @State private var title = ""
    @State private var explanation = ""
    @State private var dismissToken = 0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            content()
                .blur(radius: reduceMotion || !visible ? 0 : 7)
                .allowsHitTesting(!mounted)
                .animation(overlayAnimation, value: visible)
            if mounted {
                dialog
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.presentFeatureHelp) { nextTitle, text in
            dismissToken += 1
            title = nextTitle
            explanation = text
            closing = false
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mounted = true
                visible = false
            }
            if reduceMotion {
                visible = true
                focused = true
            } else {
                DispatchQueue.main.async {
                    visible = true
                    focused = true
                }
            }
        }
        .onChange(of: reset) { _, _ in
            if mounted { dismiss() }
        }
    }

    private var dialog: some View {
        ZStack {
            Rectangle()
                .fill(palette.ink.opacity(palette.scheme == .dark ? 0.16 : 0.06))
                .opacity(visible ? 1 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .animation(overlayAnimation, value: visible)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainPressStyle(iconOnly: true))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭说明")
                    .focused($focused)
                }
                Text(explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("知道了", action: dismiss)
                        .buttonStyle(TintCapsuleStyle())
                }
            }
            .padding(20)
            .frame(maxWidth: 440)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(palette.line, lineWidth: 1)
            }
            .shadow(color: .black.opacity(palette.scheme == .dark ? 0.4 : 0.12), radius: 24, y: 10)
            .padding(16)
            .opacity(visible ? 1 : 0)
            .scaleEffect(reduceMotion || visible ? 1 : (closing ? 0.98 : 0.96))
            .offset(y: reduceMotion || visible ? 0 : (closing ? 4 : 8))
            .animation(panelAnimation, value: visible)
        }
        .accessibilityAddTraits(.isModal)
        .onExitCommand { dismiss() }
    }

    private var overlayAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return visible
            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.24)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
    }

    private var panelAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return visible
            ? .timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
            : .timingCurve(0.22, 1, 0.36, 1, duration: 0.16)
    }

    private func dismiss() {
        guard mounted, visible else { return }
        dismissToken += 1
        let token = dismissToken
        if reduceMotion {
            visible = false
            mounted = false
            closing = false
            return
        }
        closing = true
        visible = false
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard token == dismissToken, !visible else { return }
            mounted = false
            closing = false
        }
    }
}
