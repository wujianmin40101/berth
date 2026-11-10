import Foundation
import Observation

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

struct DevService: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var directory: String
    var command: String
    var injectSecrets: Bool
}

struct CommandSnippet: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var command: String
}

struct HostsProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var body: String
}

@Observable
final class ToolboxModel {
    var services: [DevService] = []
    var snippets: [CommandSnippet] = []
    var hostsProfiles: [HostsProfile] = []
    var clipboardPins: [String] = []
    var logs: [UUID: String] = [:]
    var running: Set<UUID> = []
    var ownedPIDs: Set<Int32> = []
    var proxyHTTP = ""
    var proxyHTTPS = ""
    var proxyAll = ""
    var proxyBypass = ""
    var proxyForServices = false
    var enabledPlugins = ToolboxSettings.enabledPlugins()

    @ObservationIgnored private var processes: [UUID: Process] = [:]
    nonisolated(unsafe) private static let trackedPIDs = OwnedServicePIDs()

    init() {
        services = Self.load([DevService].self, name: "services.json") ?? []
        snippets = Self.load([CommandSnippet].self, name: "snippets.json") ?? []
        hostsProfiles = Self.load([HostsProfile].self, name: "hosts-profiles.json") ?? []
        clipboardPins = Self.load([String].self, name: "clipboard-pins.json") ?? []
        let defaults = UserDefaults.standard
        proxyHTTP = defaults.string(forKey: "macbj.proxy.http") ?? ""
        proxyHTTPS = defaults.string(forKey: "macbj.proxy.https") ?? ""
        proxyAll = defaults.string(forKey: "macbj.proxy.all") ?? ""
        proxyBypass = defaults.string(forKey: "macbj.proxy.bypass") ?? ""
        proxyForServices = defaults.bool(forKey: "macbj.proxy.services")
        _ = Self.terminateObserver
    }

    nonisolated(unsafe) private static let terminateObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: Notification.Name("NSApplicationWillTerminateNotification"),
        object: nil,
        queue: .main
    ) { _ in
        for pid in ToolboxModel.trackedPIDs.current() {
            ProcessSignal.stopTreeNow(pid: pid)
        }
    }

    private func rememberOwned() {
        Self.trackedPIDs.replace(processes.values.map(\.processIdentifier))
    }

    func setPlugin(_ plugin: ToolboxPlugin, enabled isOn: Bool) {
        var next = enabledPlugins
        if isOn {
            next.insert(plugin)
        } else {
            next.remove(plugin)
        }
        enabledPlugins = next
        ToolboxSettings.setEnabled(next)
    }

    func saveProxy() -> String? {
        switch ProxyDraft.serviceEnvironment(http: proxyHTTP, https: proxyHTTPS, all: proxyAll, bypass: proxyBypass) {
        case .failure(let failure):
            return failure.text
        case .success:
            break
        }
        let defaults = UserDefaults.standard
        defaults.set(proxyHTTP, forKey: "macbj.proxy.http")
        defaults.set(proxyHTTPS, forKey: "macbj.proxy.https")
        defaults.set(proxyAll, forKey: "macbj.proxy.all")
        defaults.set(proxyBypass, forKey: "macbj.proxy.bypass")
        defaults.set(proxyForServices, forKey: "macbj.proxy.services")
        return nil
    }

    func addService(name: String, directory: String, command: String, injectSecrets: Bool) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return L("先写服务名称。") }
        guard !trimmedCommand.isEmpty else { return L("先写启动命令。") }
        guard ShellQuote.isSingleLine(trimmedCommand) else { return L("启动命令不能换行。") }
        let folder = (directory as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            return L("项目目录不存在。")
        }
        services.append(DevService(
            id: UUID(),
            name: trimmedName,
            directory: folder,
            command: trimmedCommand,
            injectSecrets: injectSecrets
        ))
        persist(services, name: "services.json")
        return nil
    }

    func removeService(_ service: DevService) {
        stop(service, force: true)
        services.removeAll { $0.id == service.id }
        logs[service.id] = nil
        persist(services, name: "services.json")
    }

    func start(_ service: DevService) -> String? {
        guard !running.contains(service.id) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", service.command]
        process.currentDirectoryURL = URL(fileURLWithPath: service.directory)
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        if service.injectSecrets {
            for (key, value) in SecretStore.environment() {
                environment[key] = value
            }
        }
        if proxyForServices {
            switch ProxyDraft.serviceEnvironment(http: proxyHTTP, https: proxyHTTPS, all: proxyAll, bypass: proxyBypass) {
            case .success(let values):
                for (key, value) in values {
                    environment[key] = value
                }
            case .failure(let failure):
                return failure.text
            }
        }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let identifier = service.id
        let model = UncheckedBox(value: self)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor in
                model.value.appendLog(identifier, text)
            }
        }
        process.terminationHandler = { _ in
            Task { @MainActor in
                model.value.finish(identifier)
            }
        }
        do {
            try process.run()
        } catch {
            return L("没有启动这个服务。")
        }
        processes[service.id] = process
        running.insert(service.id)
        ownedPIDs.insert(process.processIdentifier)
        rememberOwned()
        appendLog(service.id, L("正在执行\n%@\n", service.command))
        return nil
    }

    func stop(_ service: DevService, force: Bool) {
        guard let process = processes[service.id] else { return }
        let pid = process.processIdentifier
        guard pid > 1 else { return }
        Task {
            await ProcessSignal.stopTree(pid: pid, force: force)
        }
    }

    func addSnippet(title: String, command: String) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !script.isEmpty else { return L("名称和命令都要填。") }
        snippets.append(CommandSnippet(id: UUID(), title: name, command: script))
        persist(snippets, name: "snippets.json")
        return nil
    }

    func removeSnippet(_ snippet: CommandSnippet) {
        snippets.removeAll { $0.id == snippet.id }
        persist(snippets, name: "snippets.json")
    }

    func addHostsProfile(name: String, body: String) -> String? {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return L("先给这份解析起个名字。") }
        if let problem = HostsFile.problem(in: body) { return problem }
        hostsProfiles.append(HostsProfile(id: UUID(), name: title, body: body))
        persist(hostsProfiles, name: "hosts-profiles.json")
        return nil
    }

    func removeHostsProfile(_ profile: HostsProfile) {
        hostsProfiles.removeAll { $0.id == profile.id }
        persist(hostsProfiles, name: "hosts-profiles.json")
    }

    func pinClipboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        clipboardPins.removeAll { $0 == trimmed }
        clipboardPins.insert(trimmed, at: 0)
        if clipboardPins.count > 30 {
            clipboardPins = Array(clipboardPins.prefix(30))
        }
        persist(clipboardPins, name: "clipboard-pins.json")
    }

    func removeClipboardPin(_ text: String) {
        clipboardPins.removeAll { $0 == text }
        persist(clipboardPins, name: "clipboard-pins.json")
    }

    func proxyCommand() -> Result<String, ToolError> {
        let pairs = [
            ("http_proxy", proxyHTTP),
            ("https_proxy", proxyHTTPS),
            ("ALL_PROXY", proxyAll),
            ("NO_PROXY", proxyBypass),
        ]
        for pair in pairs {
            if let problem = ProxyDraft.problem(in: pair.1) {
                return .failure(ToolError(problem))
            }
        }
        let lines = pairs
            .map { ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
            .map { "export \($0.0)=\(ShellQuote.singleQuoted($0.1))" }
        guard !lines.isEmpty else { return .failure(ToolError(L("还没有填写代理。"))) }
        return .success(lines.joined(separator: "\n"))
    }

    private func appendLog(_ id: UUID, _ text: String) {
        var next = (logs[id] ?? "") + text
        if next.count > 80_000 {
            next = String(next.suffix(60_000))
        }
        logs[id] = next
    }

    private func finish(_ id: UUID) {
        if let process = processes.removeValue(forKey: id) {
            ownedPIDs.remove(process.processIdentifier)
        }
        rememberOwned()
        running.remove(id)
        appendLog(id, L("\n服务已停止。\n"))
    }

    private func persist<T: Encodable>(_ value: T, name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: ToolboxPaths.file(name), options: .atomic)
    }

    private static func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        guard let data = try? Data(contentsOf: ToolboxPaths.file(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// 退出时从通知回调里读 PID。回调不在主隔离上，所以这份名单自己加锁。
nonisolated final class OwnedServicePIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [Int32] = []

    func replace(_ next: [Int32]) {
        lock.lock()
        pids = next
        lock.unlock()
    }

    func current() -> [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return pids
    }
}
