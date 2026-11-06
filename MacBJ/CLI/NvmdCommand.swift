import Foundation

nonisolated enum NvmdAction: Equatable {
    case help
    case install(String)
    case list
    case use(version: String, project: Bool)
    case current
    case uninstall(String)
    case which(String)
}

nonisolated enum NvmdParse: Equatable {
    case command(NvmdAction)
    case rejected(String)
}

nonisolated enum NvmdArguments {
    static func parse(_ arguments: [String]) -> NvmdParse {
        var args = arguments
        if args.first == "nvmd" {
            args.removeFirst()
        }
        guard let command = args.first else { return .command(.help) }
        let rest = Array(args.dropFirst())
        switch command {
        case "help", "--help", "-h":
            return rest.isEmpty ? .command(.help) : .rejected(L("help 不接受参数。"))
        case "list":
            return rest.isEmpty ? .command(.list) : .rejected(L("list 不接受参数。"))
        case "current":
            return rest.isEmpty ? .command(.current) : .rejected(L("current 不接受参数。"))
        case "install":
            guard let version = onlyVersion(in: rest) else { return .rejected(L("用法: nvmd install <版本>")) }
            return .command(.install(version))
        case "uninstall":
            guard let version = onlyVersion(in: rest) else { return .rejected(L("用法: nvmd uninstall <版本>")) }
            return .command(.uninstall(version))
        case "use":
            let project = rest.contains("--project")
            let versions = rest.filter { $0 != "--project" }
            guard versions.count == 1, let version = VersionToken.validated(versions[0]) else {
                return .rejected(L("用法: nvmd use <版本> [--project]"))
            }
            return .command(.use(version: version, project: project))
        case "which":
            let target = rest.first ?? "node"
            guard rest.count <= 1, target == "node" || target == "npm" else {
                return .rejected(L("用法: nvmd which [node|npm]"))
            }
            return .command(.which(target))
        default:
            return .rejected(L("没有这个命令: %@", command))
        }
    }

    static var help: String {
        let version = L("版本占位")
        return """
        \(L("用法:"))
          nvmd install <\(version)>
          nvmd list
          nvmd use <\(version)>
          nvmd use <\(version)> --project
          nvmd current
          nvmd uninstall <\(version)>
          nvmd which [node|npm]

        \(L("终端改完版本后，%@的版本页要点「刷新」才会更新显示。", ProductName.title))
        \(L("nvmd use --project 写入当前目录的 .nvmrc，项目页要点「刷新」才会更新显示。"))
        """
    }

    private static func onlyVersion(in rest: [String]) -> String? {
        guard rest.count == 1 else { return nil }
        return VersionToken.validated(rest[0])
    }
}

nonisolated enum NvmdCommand {
    static var shouldRun: Bool {
        let args = CommandLine.arguments
        let name = URL(fileURLWithPath: args.first ?? "").lastPathComponent
        if name == "nvmd" { return true }
        return args.dropFirst().first == "nvmd"
    }

    static func run() -> Never {
        let box = StatusBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            box.code = await perform(Array(CommandLine.arguments.dropFirst()))
            semaphore.signal()
        }
        semaphore.wait()
        fflush(stdout)
        fflush(stderr)
        exit(box.code)
    }

    static func perform(_ arguments: [String]) async -> Int32 {
        switch NvmdArguments.parse(arguments) {
        case .rejected(let message):
            return fail(message)
        case .command(.help):
            print(NvmdArguments.help)
            return 0
        case .command(.list):
            return await list()
        case .command(.current):
            return await current()
        case .command(.install(let version)):
            return await install(version)
        case .command(.uninstall(let version)):
            return await uninstall(version)
        case .command(.use(let version, let project)):
            return project ? pin(version) : await use(version)
        case .command(.which(let target)):
            return await which(target)
        }
    }

    private static func list() async -> Int32 {
        let found = await installed()
        if let message = found.error { return fail(message) }
        let rows = found.versions.filter { $0.name != "system" || $0.isCurrent }
        if rows.isEmpty {
            print(L("还没有安装 Node.js 版本。"))
            return 0
        }
        for version in rows {
            print(version.isCurrent ? "* \(version.name)" : "  \(version.name)")
        }
        return 0
    }

    private static func current() async -> Int32 {
        let found = await installed()
        if let message = found.error { return fail(message) }
        guard let version = found.versions.first(where: \.isCurrent) else {
            return fail(L("没有当前版本。"))
        }
        print(version.name)
        return 0
    }

    private static func install(_ version: String) async -> Int32 {
        let found = await installed()
        if let message = found.error { return fail(message) }
        guard let script = NodeProvider().installScript(backend: found.backend, version: version, mirror: nodeMirror()) else {
            return fail(L("这个版本不能安装。"))
        }
        return await run(script, timeout: 600)
    }

    private static func uninstall(_ version: String) async -> Int32 {
        let found = await installed()
        if let message = found.error { return fail(message) }
        guard found.versions.contains(where: { VersionOrder.key($0.name) == VersionOrder.key(version) && $0.isInstalled }) else {
            return fail(L("还没有安装 %@。", version))
        }
        guard let script = NodeProvider().uninstallScript(backend: found.backend, version: version) else {
            return fail(L("这个版本不能卸载。"))
        }
        return await run(script, timeout: 120)
    }

    private static func use(_ version: String) async -> Int32 {
        let found = await installed()
        if let message = found.error { return fail(message) }
        guard found.versions.contains(where: { VersionOrder.key($0.name) == VersionOrder.key(version) && $0.name != "system" }) else {
            return fail(L("还没有安装 %@。先执行 nvmd install %@。", version, version))
        }
        guard let script = NodeProvider().setGlobalScript(backend: found.backend, version: version) else {
            return fail(L("这个版本不能切换。"))
        }
        return await run(script, timeout: 60)
    }

    private static func pin(_ version: String) -> Int32 {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        do {
            try ProjectPins.write(kind: .node, version: version, in: directory)
        } catch let failure as RuntimeFailure {
            return fail(failure.message)
        } catch {
            return fail(L("没有写入 .nvmrc。"))
        }
        print(directory.appending(path: ".nvmrc").path)
        return 0
    }

    private static func which(_ target: String) async -> Int32 {
        let output = await Shell.run("command -v \(target)", timeout: 15)
        let path = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.status == 0, !path.isEmpty else {
            return fail(L("找不到 %@。", target))
        }
        print(path)
        return 0
    }

    private static func installed() async -> (backend: RuntimeBackend, versions: [RuntimeVersion], error: String?) {
        let output = await Shell.run(RuntimeScripts.inspect(.node))
        let probe = ProbeText.parse(output.stdout)
        let versions = NodeListing.versions(backend: probe.backend, list: probe.list)
        if probe.backend == .missing || !probe.backend.canSwitch {
            return (probe.backend, versions, L("没有检测到 fnm、nvm 或 Volta。"))
        }
        if output.status != 0, versions.isEmpty {
            let message = ShellMessage.display(output.stderr)
            return (probe.backend, versions, message.isEmpty ? L("没有读到已安装的版本。") : message)
        }
        return (probe.backend, versions, nil)
    }

    private static func nodeMirror() -> MirrorChoice {
        let raw = UserDefaults.standard.string(forKey: "macbj.mirror.node") ?? ""
        return MirrorChoice(rawValue: raw) ?? .official
    }

    private static func run(_ script: String, timeout: TimeInterval) async -> Int32 {
        let output = await Shell.run(script, timeout: timeout) { text in
            FileHandle.standardOutput.write(Data(text.utf8))
        }
        if output.status != 0 {
            let message = ShellMessage.display(output.stderr.isEmpty ? output.stdout : output.stderr)
            return fail(message.isEmpty ? L("命令没有成功。") : message)
        }
        return 0
    }

    private static func fail(_ message: String) -> Int32 {
        fputs(message + "\n", stderr)
        return 1
    }
}

nonisolated enum NvmdShim {
    static func install() {
        guard let executable = Bundle.main.executableURL else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folders = [
            support.appendingPathComponent("MacBJ/bin", isDirectory: true),
            home.appendingPathComponent(".local/bin", isDirectory: true),
        ]
        for folder in folders {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let link = folder.appendingPathComponent("nvmd")
            if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) {
                if destination == executable.path { continue }
                let owned = destination.contains("MacBJ.app/Contents/MacOS/MacBJ")
                    || destination.contains("泊位.app/Contents/MacOS/MacBJ")
                guard owned else { continue }
                try? FileManager.default.removeItem(at: link)
            } else if FileManager.default.fileExists(atPath: link.path) {
                continue
            }
            try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: executable)
        }
    }
}

nonisolated private final class StatusBox: @unchecked Sendable {
    var code: Int32 = 1
}
