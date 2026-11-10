import Foundation

struct ToolError: Error, Equatable, Sendable {
    var text: String
    init(_ text: String) { self.text = text }
}

enum ToolboxPlugin: String, CaseIterable, Identifiable {
    case ports
    case processes
    case services
    case hosts
    case secrets
    case git
    case proxy
    case snippets
    case utilities
    case machine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ports: L("端口")
        case .processes: L("进程")
        case .services: L("本地服务")
        case .hosts: "Hosts"
        case .secrets: L("密钥")
        case .git: "Git"
        case .proxy: L("代理")
        case .snippets: L("命令收藏")
        case .utilities: L("格式工具")
        case .machine: L("本机")
        }
    }

    var summary: String {
        switch self {
        case .ports: L("查看谁占用了端口，并结束那个进程。")
        case .processes: L("查看正在运行的 Node 和 Python，以及内存占用。")
        case .services: L("启动、停止项目里的开发服务，并看输出。")
        case .hosts: L("编辑本机域名解析。保存前会校验，并先做备份。")
        case .secrets: L("变量放在钥匙串里。启动本地服务时可以注入，默认不显示原文。")
        case .git: L("查看和修改全局用户名、邮箱、别名，以及生成 SSH 公钥。")
        case .proxy: L("只使用你自己填写的代理。不会写入 shell 配置。")
        case .snippets: L("把常用命令留在这里，需要时复制或运行。")
        case .utilities: L("格式化 JSON、转换时间戳，以及 Base64 和 URL 编解码。")
        case .machine: L("内存分布、卸载应用、清理缓存和优化速度放在一起。")
        }
    }

    var icon: String {
        switch self {
        case .ports: "point.3.connected.trianglepath.dotted"
        case .processes: "memorychip"
        case .services: "server.rack"
        case .hosts: "network"
        case .secrets: "key"
        case .git: "arrow.triangle.branch"
        case .proxy: "globe"
        case .snippets: "terminal"
        case .utilities: "wrench.adjustable"
        case .machine: "desktopcomputer"
        }
    }

    /// 和「把项目跑起来」直接相关，第一次打开工具箱时就启用。
    var startsEnabled: Bool {
        switch self {
        case .ports, .processes, .services: true
        default: false
        }
    }
}

enum ToolboxSettings {
    private static let enabledKey = "macbj.toolbox.enabled"
    private static let maintenanceKey = "macbj.toolbox.maintenance"
    private static let legacyMaintenance = ["memory", "uninstall", "caches", "speed"]

    static func enabledPlugins() -> Set<ToolboxPlugin> {
        let defaults = UserDefaults.standard
        guard var stored = defaults.array(forKey: enabledKey) as? [String] else {
            return Set(ToolboxPlugin.allCases.filter(\.startsEnabled))
        }
        if stored.contains(where: { legacyMaintenance.contains($0) }) {
            stored.removeAll { legacyMaintenance.contains($0) }
            if !stored.contains(ToolboxPlugin.machine.rawValue) {
                stored.append(ToolboxPlugin.machine.rawValue)
            }
            defaults.set(stored, forKey: enabledKey)
            defaults.set(true, forKey: maintenanceKey)
        }
        return Set(stored.compactMap(ToolboxPlugin.init(rawValue:)))
    }

    static func setEnabled(_ plugins: Set<ToolboxPlugin>) {
        UserDefaults.standard.set(plugins.map(\.rawValue).sorted(), forKey: enabledKey)
    }
}

enum ToolboxPaths {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("MacBJ", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func file(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}

enum ShellQuote {
    static func isSingleLine(_ value: String) -> Bool {
        !value.contains { $0 == "\n" || $0 == "\r" || $0 == "\0" }
    }

    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
