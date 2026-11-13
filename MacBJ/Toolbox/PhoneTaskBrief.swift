import AppKit
import CryptoKit
import Foundation

enum PhoneAIHost: String, CaseIterable, Identifiable {
    case muse
    case claudeCode
    case codex
    case openCode
    case cursor
    case deepSeek
    case workBuddy
    case doubao
    case grok
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muse: "Muse"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .openCode: "OpenCode"
        case .cursor: "Cursor"
        case .deepSeek: "DeepSeek"
        case .workBuddy: "WorkBuddy"
        case .doubao: L("豆包工作")
        case .grok: "Grok"
        case .other: L("其他 AI")
        }
    }

    /// 本机能直接打开的应用。没有对应应用时只复制提示词。
    var bundleIdentifier: String? {
        switch self {
        case .workBuddy: PhoneTaskBrief.workBuddyBundle
        case .doubao: PhoneTaskBrief.doubaoBundle
        case .cursor: "com.todesktop.230313mzl4w4u92"
        default: nil
        }
    }
}

/// 给用户自己的 AI 的提示词。安装词来自 iPhone Use 的 README；任务词让对方把脚本写进 `scripts/tasks`。
enum PhoneTaskBrief {
    struct Written: Equatable {
        var slug: String
        var markdown: String
        var file: URL
        var command: String
        var scriptExists: Bool
    }

    static let doubaoBundle = "com.bot.pc.doubao"
    static let workBuddyBundle = "com.tencent.workbuddy.mac"

    static func slug(title: String) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(name.utf8))
        let hex = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        let ascii = name.lowercased().unicodeScalars.filter { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
        }
        let stem = String(String.UnicodeScalarView(ascii.prefix(16)))
        if stem.count >= 2 { return "\(stem)-\(hex)" }
        return "task-\(hex)"
    }

    static func command(for slug: String) -> String {
        "python3 scripts/tasks/\(slug).py"
    }

    /// 命令正好指向 `scripts/tasks` 里还不存在的脚本时，返回相对路径。
    static func missingScript(command: String, checkout: URL) -> String? {
        let line = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "python3 scripts/tasks/"
        guard line.hasPrefix(prefix), line.hasSuffix(".py") else { return nil }
        let name = String(line.dropFirst(prefix.count).dropLast(3))
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        let relative = "scripts/tasks/\(name).py"
        let script = checkout
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("tasks", isDirectory: true)
            .appendingPathComponent(name + ".py")
        var directory: ObjCBool = false
        if FileManager.default.fileExists(atPath: script.path, isDirectory: &directory), !directory.boolValue {
            return nil
        }
        return relative
    }

    static func installPrompt(_ host: PhoneAIHost) -> String {
        switch host {
        case .codex:
            return """
            请帮我安装和配置 iPhone Use：
            https://github.com/zhongerxin/iPhone-use

            先读取仓库 README 和安装脚本，检查本机 Codex CLI、Python、Node.js、npm、
            完整 Xcode，以及通过 USB 连接的 iPhone。把项目放到合适的本机目录，
            运行 sh scripts/install.sh 安装插件。

            如果当前聊天还没有加载新工具，明确告诉我重连或新开聊天后继续。
            工具可用后读取 iphone-use-setup 技能，检查现有配置，优先复用已有 WDA。
            首次配置时发现我的设备，使用我自己的 Apple 开发团队和可签名 bundle ID，
            获取固定版本 WDA、配置签名、构建并启动，直到 pua_ready 返回 ready=true，
            然后打开手机屏幕。不要照搬作者的设备标识或签名信息。

            缺少依赖时说明具体缺项并帮助安装。Apple 账号登录、设备信任、开发者模式
            或解锁需要我操作时，告诉我明确步骤，等我完成再继续。
            """
        case .workBuddy:
            return """
            请在这台 Mac 上安装 iPhone Use，让 WorkBuddy 通过 USB 操作我的真实 iPhone：
            https://github.com/zhongerxin/iPhone-use

            先读取 README.md、workbuddy/README.md 和安装脚本，检查 Python、Node.js、npm、
            完整 Xcode 和 USB iPhone。克隆或复用本地源码，保留已有改动，
            在源码目录运行 python3 workbuddy/install.py；不要运行 Codex 安装脚本。
            在 WorkBuddy「连接器管理」里信任并启用 iphone_use，然后新开会话加载工具和技能。
            如果这些界面步骤需要我操作，给出具体位置，等我完成后继续。

            工具可用后读取 iphone-use-setup，先查询 setup status，复用已有配置、健康 WDA
            或正在运行的启动任务；首次配置使用我自己的设备和 Apple 开发团队完成签名与启动。
            确认 pua_ready 返回 ready=true 后调用一次 pua_screen()，在侧边栏显示实时手机画面，
            再在 iPhone 计算器中验证 12×34=408。Apple 登录、信任、开发者模式或解锁
            需要我接管时，说明具体步骤并等我完成；不要照搬作者的设备标识或签名信息。
            """
        case .doubao:
            return """
            请在这台 Mac 上安装 iPhone Use，让豆包工作通过 USB 操作我的真实 iPhone：
            https://github.com/zhongerxin/iPhone-use

            在「本地电脑」任务中先读取 README.md、doubao/README.md 和安装脚本，
            检查 Python、Node.js、npm、完整 Xcode 和 USB iPhone。克隆或复用本地源码，
            保留已有改动，在源码目录运行 python3 doubao/install.py；不要运行 Codex 安装脚本。
            按安装器输出，在「插件 · 技能 · 伙伴」中新建名为 iphone_use 的 STDIO 连接器，
            命令和参数使用输出的绝对路径，并分别上传安装目录下的 iphone-use、iphone-use-setup
            两个技能文件夹。启用连接器和技能，再新开「本地电脑」任务；已有连接器更新后关闭再打开。
            如果这些界面步骤需要我操作，给出具体位置和路径，等我完成后继续。

            工具可用后读取 iphone-use-setup，先查询 setup status，复用已有配置、健康 WDA
            或正在运行的启动任务；首次配置使用我自己的设备和 Apple 开发团队完成签名与启动。
            确认 pua_ready 返回 ready=true 后调用一次 pua_screen()，在右侧 MCP App 显示实时手机画面，
            再在 iPhone 计算器中验证 12×34=408。Apple 登录、信任、开发者模式或解锁
            需要我接管时，说明具体步骤并等我完成；不要照搬作者的设备标识或签名信息。
            """
        case .grok, .muse, .claudeCode, .openCode, .cursor, .deepSeek:
            return localInstall(name: host.title)
        case .other:
            return """
            请在这台 Mac 上安装和配置 iPhone Use：
            https://github.com/zhongerxin/iPhone-use

            先读取 README。按我实际使用的工具选一条，不要几条一起跑：
            Codex 在源码目录运行 sh scripts/install.sh。
            WorkBuddy 运行 python3 workbuddy/install.py，不要运行 Codex 安装脚本。
            豆包工作运行 python3 doubao/install.py，不要运行 Codex 安装脚本。
            没有对应安装器的工具，不要编造一个新的 install.py。

            检查 Python、Node.js、npm、完整 Xcode 和 USB iPhone。克隆或复用本地源码，保留已有改动。
            工具可用后读取 iphone-use-setup，优先复用已有 WDA。首次配置使用我自己的 Apple 开发团队
            和可签名 bundle ID，直到 pua_ready 返回 ready=true。
            不要照搬作者的设备标识或签名信息。
            Apple 账号登录、设备信任、开发者模式或解锁需要我操作时，告诉我明确步骤，等我完成再继续。
            """
        }
    }

    private static func localInstall(name: String) -> String {
        """
        请在这台 Mac 上安装和配置 iPhone Use。\(name) 没有单独的安装器，按仓库 README 的本机步骤做：
        https://github.com/zhongerxin/iPhone-use

        先读取 README 和 scripts/install.sh，检查 Python、Node.js、npm、完整 Xcode，
        以及通过 USB 连接的 iPhone。克隆或复用本地源码，保留已有改动。
        本机有 Codex CLI 时，在源码目录运行 sh scripts/install.sh。
        没有 Codex CLI 时不要编造 \(name) 的 install.py，说明缺的是 Codex CLI，并停在源码已经放好的那一步。
        不要运行 workbuddy/install.py 或 doubao/install.py，除非我改口说要装到那两个应用。

        工具可用后读取 iphone-use-setup，优先复用已有 WDA。首次配置使用我自己的 Apple 开发团队
        和可签名 bundle ID，直到 pua_ready 返回 ready=true，再打开手机屏幕。
        不要照搬作者的设备标识或签名信息。
        Apple 账号登录、设备信任、开发者模式或解锁需要我操作时，告诉我明确步骤，等我完成再继续。
        """
    }

    static func action(kind: PhoneTaskKind, note: String) -> String {
        let extra = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .punchIn:
            let base = "到点做上班打卡。运行已有的 scripts/punch.py，参数是 in --now。打开飞书顶部固定的假勤，只给这一班还没打卡的账号打卡。不要点消息列表里会换位置的假勤。不要输入密码或解锁。"
            return extra.isEmpty ? base : base + "\n还要：" + extra
        case .punchOut:
            let base = "到点做下班打卡。运行已有的 scripts/punch.py，参数是 out --now。打开飞书顶部固定的假勤，只给这一班还没打下班卡的账号打卡。不要点消息列表里会换位置的假勤。不要输入密码或解锁。"
            return extra.isEmpty ? base : base + "\n还要：" + extra
        case .command:
            return extra
        }
    }

    static func taskPrompt(
        host: PhoneAIHost,
        title: String,
        note: String,
        schedule: String,
        rootPath: String,
        slug: String,
        kind: PhoneTaskKind,
        weekdays: [Int],
        hour: Int,
        minute: Int
    ) -> String {
        let root = rootPath
        let script = "scripts/tasks/\(slug).py"
        let file = "scripts/tasks/\(slug).task.json"
        let opening: String
        switch host {
        case .codex:
            opening = "请在这台 Mac 上，给泊位写一个可定时执行的 iPhone Use 任务文件。不要运行 sh scripts/install.sh，项目目录里已经有源码。"
        case .workBuddy:
            opening = "请在 WorkBuddy 里改本机文件，给泊位写一个可定时执行的任务文件。不要运行 Codex 安装脚本。如果工具还没加载，告诉我到「连接器管理」信任 iphone_use 并新开会话，等我完成再继续。"
        case .doubao:
            opening = "请在豆包工作的「本地电脑」任务里改本机文件，给泊位写一个可定时执行的任务文件。不要运行 Codex 安装脚本。如果连接器或技能需要我点，给出具体位置，等我完成再继续。"
        case .muse, .claudeCode, .openCode, .cursor, .deepSeek, .grok:
            opening = "请在 \(host.title) 里直接改本机项目文件，给泊位写一个可定时执行的任务文件。\(host.title) 没有单独的安装器，不要编造安装脚本，也不要运行 sh scripts/install.sh。"
        case .other:
            opening = "请在这台 Mac 上直接改项目文件，给泊位写一个可定时执行的任务文件。不要运行安装脚本，也不要编造新的 install.py。"
        }
        let scriptStep: String
        if kind == .command {
            scriptStep = """
            脚本必须完成上面的要做的事，不能改成别的任务。把脚本写到 \(root)/\(script)。用 Python 3。操作手机参考 scripts/punch.py 里的 ensure_service 和 call，从 server 使用 iphone_use.Runtime，状态目录是 ~/.local/share/iphone-use。也可以在项目根目录调用 python3 scripts/phone.py <工具名> '<一行 JSON>'。工具名以 pua_ 开头，用法见 skills/iphone-use/SKILL.md。
            开始前先看服务是否可用，缺了再启动一次，然后确认 READY。不要整套重装。
            手机锁屏，或页面要密码、PIN、Face ID、验证码时立刻停。打印一行 stopped: phone-locked，退出码用 1。不要输入密码、PIN 或验证码，也不要替我解锁。
            成功时先打印要做的事，再打印一行人能看懂的结果，退出码 0。失败打印原因，退出码不要是 0。
            写完后在项目目录执行 python3 -m py_compile \(script)。
            不要改 scripts/punch.py，不要改已有的上班、下班定时，不要改 ~/.local/share/iphone-use 里的设备配置。
            不要在这次对话里操作手机，除非我明确说现在就执行。
            """
        } else {
            scriptStep = "这次不要另写 Python 文件。到点由泊位按上面的要做的事执行已有的 scripts/punch.py。不要改 scripts/punch.py，不要改已有的上班、下班定时。"
        }
        return """
        \(opening)

        这次定时要做的事，只能做这件事：
        \(note)

        名称：\(title)
        时间：\(schedule)
        项目目录：\(root)
        https://github.com/zhongerxin/iPhone-use
        到点由泊位启动。脚本里不要再等时间窗口，也不要自己做定时。

        \(scriptStep)

        然后把下面这份 JSON 原样写到 \(root)/\(file)。不要加注释，不要改字段名。
        \(taskFileJSON(title: title, note: note, kind: kind, slug: slug, weekdays: weekdays, hour: hour, minute: minute))

        不要写 phone-tasks.json，不要改 LaunchAgents。
        写完就停。我回到泊位点刷新，泊位会读取 scripts/tasks 里的 .task.json，自己挂上定时。
        """
    }

    static func taskFileJSON(title: String, note: String, kind: PhoneTaskKind, slug: String, weekdays: [Int], hour: Int, minute: Int) -> String {
        let days = weekdays.sorted {
            PhoneSlot.weekOrder.firstIndex(of: $0) ?? 0 < PhoneSlot.weekOrder.firstIndex(of: $1) ?? 0
        }.map(String.init).joined(separator: ", ")
        let scriptLine = kind == .command ? "\n  \"script\": \"scripts/tasks/\(slug).py\"," : ""
        return """
        {
          "title": \(jsonString(title)),
          "note": \(jsonString(note)),
          "kind": "\(kind.rawValue)",\(scriptLine)
          "weekdays": [\(days)],
          "hour": \(hour),
          "minute": \(minute)
        }
        """
    }

    private static func jsonString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    static func write(
        title: String,
        note: String,
        schedule: String,
        checkout: URL,
        host: PhoneAIHost = .codex,
        kind: PhoneTaskKind,
        weekdays: [Int],
        hour: Int,
        minute: Int
    ) throws -> Written {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw ToolError(L("先写名称。")) }
        if name.contains(where: { $0 == "\n" || $0 == "\r" }) { throw ToolError(L("名称不能换行。")) }
        if name.count > 40 { throw ToolError(L("名称太长。")) }
        let detail = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty { throw ToolError(L("先写下这个定时要做什么。")) }
        let root = checkout.standardizedFileURL
        var punchDirectory: ObjCBool = false
        let punch = root.appendingPathComponent("scripts/punch.py")
        guard FileManager.default.fileExists(atPath: punch.path, isDirectory: &punchDirectory), !punchDirectory.boolValue else {
            throw ToolError(L("这个目录里没有 scripts/punch.py。"))
        }
        let slug = slug(title: name)
        let folder = root
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(slug + ".md")
        let script = folder.appendingPathComponent(slug + ".py")
        let text = taskPrompt(
            host: host,
            title: name,
            note: detail,
            schedule: schedule,
            rootPath: root.path,
            slug: slug,
            kind: kind,
            weekdays: weekdays,
            hour: hour,
            minute: minute
        )
        try Data(text.utf8).write(to: file, options: .atomic)
        var scriptDirectory: ObjCBool = false
        let scriptExists = FileManager.default.fileExists(atPath: script.path, isDirectory: &scriptDirectory) && !scriptDirectory.boolValue
        return Written(slug: slug, markdown: text, file: file, command: command(for: slug), scriptExists: scriptExists)
    }

    static func open(_ bundle: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
