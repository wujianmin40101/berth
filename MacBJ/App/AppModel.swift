import Foundation
import Observation

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
}

@Observable
final class AppModel {
    var selectedKind: RuntimeKind = .node
    var snapshots: [RuntimeKind: RuntimeSnapshot] = [:]
    /// 某个运行时的目录被替换时加一。列表用它判断要不要重新排序，避免逐项比较。
    var catalogRevision: [RuntimeKind: Int] = [:]
    var loading: Set<RuntimeKind> = []
    var switching: Set<RuntimeKind> = []
    var failures: [RuntimeKind: String] = [:]
    var selection: [RuntimeKind: RuntimeVersion.ID] = [:]
    var mirrors: [RuntimeKind: MirrorChoice]
    var aliases: [RuntimeKind: [VersionAlias]] = [:]
    var projects: [ProjectRecord] = []
    var selectedProjectPath: String?
    var projectDirectory: URL?
    var projectSummaries: [String: String] = [:]
    var projectNotice: String?
    var bindPrompt: BindPrompt?
    var removingProject: ProjectRecord?
    var pins: [RuntimeKind: ProjectPin] = [:]
    var hookStatus: HookStatus = .missing
    var confirmUninstall = false
    var showAliases = false
    var showHook = false
    var aliasName = ""
    var aliasVersion = ""
    var session = CommandSession()
    let loadsOnAppear: Bool

    @ObservationIgnored
    private var tasks: [RuntimeKind: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var scopedProject: URL?

    init(
        snapshots: [RuntimeKind: RuntimeSnapshot] = [:],
        loadsOnAppear: Bool = true
    ) {
        self.snapshots = snapshots
        self.loadsOnAppear = loadsOnAppear
        mirrors = [
            .node: MirrorSettings.choice(for: .node),
            .python: MirrorSettings.choice(for: .python),
        ]
        projects = Self.loadProjects()
        let saved = UserDefaults.standard.string(forKey: Self.selectedProjectKey)
        if let path = saved ?? projects.first?.path, projects.contains(where: { $0.path == path }) {
            selectProject(path: path)
        }
    }

    func reloadPins() {
        guard let projectDirectory else {
            pins = [:]
            refreshProjectSummaries()
            return
        }
        for kind in RuntimeKind.allCases {
            pins[kind] = provider(for: kind).projectPin(in: projectDirectory)
        }
        refreshProjectSummaries()
    }

    func refreshAll() {
        reloadHookStatus()
        for kind in RuntimeKind.allCases {
            refresh(kind)
        }
    }

    func refresh(_ kind: RuntimeKind) {
        tasks[kind]?.cancel()
        loading.insert(kind)
        failures[kind] = nil
        let mirror = mirrors[kind] ?? .official
        let model = UncheckedBox(value: self)
        let task = Task {
            let provider = model.value.provider(for: kind)
            let snapshot = await provider.catalog(mirror: mirror)
            let found = await provider.aliases(backend: snapshot.backend)
            guard !Task.isCancelled else { return }
            model.value.snapshots[kind] = snapshot
            model.value.catalogRevision[kind, default: 0] += 1
            model.value.aliases[kind] = found
            if let projectDirectory = model.value.projectDirectory {
                model.value.pins[kind] = provider.projectPin(in: projectDirectory)
            }
            model.value.loading.remove(kind)
            if model.value.selection[kind] == nil, let current = snapshot.installed.first(where: \.isCurrent) {
                model.value.selection[kind] = current.id
            }
        }
        tasks[kind] = task
    }

    func performPrimary(_ kind: RuntimeKind) {
        guard let snapshot = snapshots[kind], let version = selectedVersion(kind) else { return }
        if version.isInstalled {
            setGlobal(kind, version: version, backend: snapshot.backend)
        } else {
            install(kind, version: version, backend: snapshot.backend)
        }
    }

    func requestUninstall(_ kind: RuntimeKind) {
        guard let version = selectedVersion(kind), version.isInstalled, version.name != "system" else { return }
        if version.isCurrent {
            confirmUninstall = true
        } else {
            uninstall(kind)
        }
    }

    func uninstallSelected() {
        uninstall(selectedKind)
    }

    func requestBind(_ kind: RuntimeKind, version: String) {
        guard version != "system", VersionToken.validated(version) != nil else {
            projectNotice = L("这个版本不能绑定。")
            return
        }
        guard projectDirectory != nil else {
            bindPrompt = .needProject
            return
        }
        bindPrompt = .confirm(kind, version)
    }

    func writeProjectPin(_ kind: RuntimeKind, version: String) {
        guard let projectDirectory else {
            bindPrompt = .needProject
            return
        }
        let folder = projectDirectory.lastPathComponent
        let file = ProjectPins.fileName(for: kind) ?? L("版本文件")
        do {
            try provider(for: kind).writeProjectPin(version, in: projectDirectory)
            pins[kind] = provider(for: kind).projectPin(in: projectDirectory)
            projectNotice = L("已把 %@ %@ 写入「%@」的 %@。", kind.title, version, folder, file)
            refreshProjectSummaries()
        } catch let failure as RuntimeFailure {
            projectNotice = failure.message
            failures[kind] = failure.message
        } catch {
            projectNotice = L("没有写入 %@。", file)
            failures[kind] = projectNotice
        }
    }

    func setMirror(_ choice: MirrorChoice, for kind: RuntimeKind) {
        mirrors[kind] = choice
        MirrorSettings.set(choice, for: kind)
        refresh(kind)
    }

    func addProject(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let bookmark = (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) ?? Data()
        if let index = projects.firstIndex(where: { $0.path == path }) {
            projects[index].bookmark = bookmark
        } else {
            projects.append(ProjectRecord(path: path, bookmark: bookmark))
        }
        saveProjects()
        selectProject(path: path)
    }

    func selectProject(path: String) {
        guard let record = projects.first(where: { $0.path == path }) else { return }
        guard let url = resolve(record) else {
            projectNotice = L("「%@」的目录已经不在了。", record.name)
            return
        }
        if selectedProjectPath != path {
            scopedProject?.stopAccessingSecurityScopedResource()
            _ = url.startAccessingSecurityScopedResource()
            scopedProject = url
        }
        selectedProjectPath = path
        projectDirectory = url
        UserDefaults.standard.set(path, forKey: Self.selectedProjectKey)
        reloadPins()
        projectNotice = nil
    }

    func removeProject(_ record: ProjectRecord) {
        if selectedProjectPath == record.path {
            scopedProject?.stopAccessingSecurityScopedResource()
            scopedProject = nil
            selectedProjectPath = nil
            projectDirectory = nil
            pins = [:]
            UserDefaults.standard.removeObject(forKey: Self.selectedProjectKey)
        }
        projects.removeAll { $0.path == record.path }
        projectSummaries[record.path] = nil
        saveProjects()
        if projectDirectory == nil, let next = projects.first {
            selectProject(path: next.path)
        } else {
            refreshProjectSummaries()
        }
    }

    func addAlias() {
        let kind = selectedKind
        guard let snapshot = snapshots[kind] else { return }
        let name = aliasName
        let version = aliasVersion.isEmpty ? (selectedVersion(kind)?.name ?? "") : aliasVersion
        let model = UncheckedBox(value: self)
        Task {
            do {
                try await model.value.provider(for: kind).setAlias(name: name, version: version, backend: snapshot.backend)
                model.value.aliases[kind] = await model.value.provider(for: kind).aliases(backend: snapshot.backend)
                model.value.aliasName = ""
                model.value.aliasVersion = ""
            } catch let failure as RuntimeFailure {
                model.value.failures[kind] = failure.message
            } catch {
                model.value.failures[kind] = L("没有保存别名。")
            }
        }
    }

    func removeAlias(_ alias: VersionAlias) {
        let kind = selectedKind
        guard let snapshot = snapshots[kind] else { return }
        let model = UncheckedBox(value: self)
        Task {
            do {
                try await model.value.provider(for: kind).removeAlias(name: alias.name, backend: snapshot.backend)
                model.value.aliases[kind] = await model.value.provider(for: kind).aliases(backend: snapshot.backend)
            } catch let failure as RuntimeFailure {
                model.value.failures[kind] = failure.message
            } catch {
                model.value.failures[kind] = L("没有删除别名。")
            }
        }
    }

    func reloadHookStatus() {
        let text = (try? String(contentsOf: ShellHook.userZshrc, encoding: .utf8)) ?? ""
        hookStatus = ShellHook.status(of: text)
    }

    func installHook() {
        do {
            try ShellHook.apply(to: ShellHook.userZshrc)
            reloadHookStatus()
            showHook = false
        } catch let failure as RuntimeFailure {
            failures[selectedKind] = failure.message
        } catch {
            failures[selectedKind] = L("没有写入 shell 配置。")
        }
    }

    func sidebarDetail(for kind: RuntimeKind) -> String {
        if loading.contains(kind), snapshots[kind] == nil {
            return L("读取中")
        }
        guard let snapshot = snapshots[kind] else { return " " }
        if let current = snapshot.installed.first(where: \.isCurrent) {
            return current.title
        }
        if snapshot.installed.isEmpty {
            return snapshot.backend == .missing ? L("未检测") : L("无版本")
        }
        return snapshot.backend.title
    }

    func primaryTitle(for kind: RuntimeKind) -> String {
        guard let version = selectedVersion(kind) else { return L("设为全局默认") }
        if !version.isInstalled { return L("安装此版本") }
        if version.isCurrent { return L("已是默认") }
        return L("设为全局默认")
    }

    func canPerformPrimary(_ kind: RuntimeKind) -> Bool {
        guard !session.isRunning,
              !switching.contains(kind),
              let snapshot = snapshots[kind],
              snapshot.canSwitch,
              let version = selectedVersion(kind),
              version.name != "system"
        else { return false }
        if !version.isInstalled { return true }
        return !version.isCurrent
    }

    func canUninstall(_ kind: RuntimeKind) -> Bool {
        guard !session.isRunning,
              let snapshot = snapshots[kind],
              snapshot.canSwitch,
              let version = selectedVersion(kind)
        else { return false }
        return version.isInstalled && version.name != "system"
    }

    func canBind(_ kind: RuntimeKind) -> Bool {
        guard projectDirectory != nil, let version = selectedVersion(kind) else { return false }
        return version.name != "system" && VersionToken.validated(version.name) != nil
    }

    func projectTitle(for kind: RuntimeKind) -> String {
        guard let projectDirectory else { return L("未选择项目") }
        let folder = projectDirectory.lastPathComponent
        guard let pin = pins[kind] else { return folder }
        let suffix = pin.writable ? pin.version : L("%@（只读）", pin.version)
        return L("%@ · %@ %@", folder, pin.fileName, suffix)
    }

    func pinMatches(_ version: RuntimeVersion, kind: RuntimeKind) -> Bool {
        guard let pin = pins[kind] else { return false }
        return VersionOrder.key(pin.version) == VersionOrder.key(version.name)
    }

    func refreshProjectSummaries() {
        var next: [String: String] = [:]
        for record in projects {
            let url = URL(fileURLWithPath: record.path, isDirectory: true)
            let parts = RuntimeKind.allCases.compactMap { kind -> String? in
                guard let pin = provider(for: kind).projectPin(in: url) else { return nil }
                return L("%@ %@", kind.title, pin.version)
            }
            next[record.path] = parts.isEmpty ? L("还没有绑定") : parts.joined(separator: " · ")
        }
        projectSummaries = next
    }

    private func resolve(_ record: ProjectRecord) -> URL? {
        if !record.bookmark.isEmpty {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: record.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                return url
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: record.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: record.path, isDirectory: true)
    }

    private func saveProjects() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        UserDefaults.standard.set(data, forKey: Self.projectsKey)
    }

    private static func loadProjects() -> [ProjectRecord] {
        guard let data = UserDefaults.standard.data(forKey: projectsKey),
              let records = try? JSONDecoder().decode([ProjectRecord].self, from: data) else {
            return []
        }
        return records
    }

    private static let projectsKey = "macbj.projects"
    private static let selectedProjectKey = "macbj.project.selected"

    private func selectedVersion(_ kind: RuntimeKind) -> RuntimeVersion? {
        guard let id = selection[kind] else { return nil }
        return snapshots[kind]?.versions.first { $0.id == id }
    }

    private func setGlobal(_ kind: RuntimeKind, version: RuntimeVersion, backend: RuntimeBackend) {
        guard let script = provider(for: kind).setGlobalScript(backend: backend, version: version.name) else {
            failures[kind] = L("这个版本不能切换。")
            return
        }
        switching.insert(kind)
        failures[kind] = nil
        let model = UncheckedBox(value: self)
        Task {
            do {
                try await ShellCommand.succeed(script)
                guard !Task.isCancelled else { return }
                model.value.switching.remove(kind)
                model.value.refresh(kind)
            } catch let failure as RuntimeFailure {
                model.value.switching.remove(kind)
                model.value.failures[kind] = failure.message
            } catch {
                model.value.switching.remove(kind)
                model.value.failures[kind] = L("切换没有成功。")
            }
        }
    }

    private func install(_ kind: RuntimeKind, version: RuntimeVersion, backend: RuntimeBackend) {
        guard let script = provider(for: kind).installScript(
            backend: backend,
            version: version.name,
            mirror: mirrors[kind] ?? .official
        ) else {
            failures[kind] = L("这个版本不能安装。")
            return
        }
        run(kind, script: script, timeout: 600)
    }

    private func uninstall(_ kind: RuntimeKind) {
        guard let snapshot = snapshots[kind], let version = selectedVersion(kind) else { return }
        guard let script = provider(for: kind).uninstallScript(backend: snapshot.backend, version: version.name) else {
            failures[kind] = L("这个版本不能卸载。")
            return
        }
        run(kind, script: script, timeout: 120)
    }

    private func run(_ kind: RuntimeKind, script: String, timeout: TimeInterval) {
        failures[kind] = nil
        let handle = ShellHandle()
        let token = session.begin(script, handle: handle)
        let session = UncheckedBox(value: self.session)
        let model = UncheckedBox(value: self)
        let handler: @Sendable (String) -> Void = { text in
            Task { @MainActor in
                guard session.value.isCurrent(token) else { return }
                session.value.append(text)
            }
        }
        let task = Task {
            let output = await Shell.run(script, timeout: timeout, handle: handle, onOutput: handler)
            guard session.value.isCurrent(token) else { return }
            if handle.isCancelled || output.status == 130 {
                session.value.append(L("\n已取消。\n"))
                session.value.finish(token)
                return
            }
            session.value.finish(token)
            if output.status != 0 {
                let message = ShellMessage.display(output.stderr.isEmpty ? output.stdout : output.stderr)
                model.value.failures[kind] = message.isEmpty ? L("命令没有成功。") : message
            } else {
                model.value.refresh(kind)
            }
        }
        session.value.track(task)
    }

    private func provider(for kind: RuntimeKind) -> any RuntimeProvider {
        ProviderRegistry.provider(for: kind)
    }
}

struct ProjectRecord: Codable, Identifiable, Equatable, Hashable {
    var path: String
    var bookmark: Data

    var id: String { path }

    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum BindPrompt: Identifiable {
    case needProject
    case confirm(RuntimeKind, String)

    var id: String {
        switch self {
        case .needProject:
            "need"
        case .confirm(let kind, let version):
            "\(kind.rawValue) \(version)"
        }
    }
}

extension AppModel {
    static var preview: AppModel {
        let node = RuntimeSnapshot(
            kind: .node,
            backend: .nvm,
            versions: [
                RuntimeVersion(name: "v22.23.4", isCurrent: true, isInstalled: true, channel: .lts),
                RuntimeVersion(name: "v20.20.2", isCurrent: false, isInstalled: true, channel: .deprecated),
                RuntimeVersion(name: "v24.11.0", isCurrent: false, isInstalled: false, channel: .lts),
            ],
            loadError: nil
        )
        let python = RuntimeSnapshot(
            kind: .python,
            backend: .uv,
            versions: [
                RuntimeVersion(name: "3.14.3", isCurrent: true, isInstalled: true, channel: .stable),
                RuntimeVersion(name: "3.12.8", isCurrent: false, isInstalled: false, channel: .stable),
            ],
            loadError: nil
        )
        let model = AppModel(
            snapshots: [.node: node, .python: python],
            loadsOnAppear: false
        )
        model.selection[.node] = "v22.23.4"
        model.selection[.python] = "3.14.3"
        model.hookStatus = .missing
        return model
    }
}
