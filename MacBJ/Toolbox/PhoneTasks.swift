import Darwin
import Foundation

/// 泊位里看到的一条定时。已有的上班、下班来自 iPhone Use 的 launchd；新增的存在泊位自己的清单里。
struct PhoneTaskSnapshot: Equatable, Identifiable {
    var id: String
    var title: String
    var note: String
    var kind: PhoneTaskKind
    var command: String
    var slots: [PhoneSlot]
    var enabled: Bool
    var owned: Bool
    var loaded: Bool
    var agent: URL?
    /// `scripts/tasks` 里的 `.task.json` 文件名。没有这个字段的是以前手动增加的定时。
    var source: String?
}

enum PhoneTaskKind: String, Codable, Equatable {
    case punchIn
    case punchOut
    case command
}

struct PhoneSlot: Codable, Equatable, Identifiable {
    /// launchd 的 Weekday：1 是周一，6 是周六，0 是周日。
    var weekday: Int
    var hour: Int
    var minute: Int

    var id: String { "\(weekday)-\(hour)-\(minute)" }

    static let weekOrder = [1, 2, 3, 4, 5, 6, 0]

    static func normalize(weekday: Int) -> Int? {
        if weekday == 7 { return 0 }
        if (0...6).contains(weekday) { return weekday }
        return nil
    }
}

struct PhoneTaskDraft: Equatable {
    var title: String
    var note: String
    var kind: PhoneTaskKind
    var command: String
    var weekdays: Set<Int>
    var hour: Int
    var minute: Int

    func problem(scriptReady: Bool) -> String? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return L("先写名称。") }
        if name.contains(where: { $0 == "\n" || $0 == "\r" }) || title.contains(where: { $0 == "\n" || $0 == "\r" }) {
            return L("名称不能换行。")
        }
        if name.count > 40 { return L("名称太长。") }
        if weekdays.isEmpty { return L("至少选一个星期。") }
        if weekdays.contains(where: { PhoneSlot.normalize(weekday: $0) == nil }) || !(0...23).contains(hour) || !(0...59).contains(minute) {
            return L("时间要在 0:00 到 23:59。")
        }
        if kind != .command { return scriptReady ? nil : L("没有找到打卡脚本。") }
        let line = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return L("先写要执行的命令。") }
        if line.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }) { return L("命令不能换行。") }
        return nil
    }

    var slots: [PhoneSlot] {
        weekdays.compactMap { weekday in
            guard let weekday = PhoneSlot.normalize(weekday: weekday) else { return nil }
            return PhoneSlot(weekday: weekday, hour: hour, minute: minute)
        }
        .sorted { lhs, rhs in
            PhoneSlot.weekOrder.firstIndex(of: lhs.weekday) ?? 0 < PhoneSlot.weekOrder.firstIndex(of: rhs.weekday) ?? 0
        }
    }
}

struct SavedPhoneTask: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var note: String
    var kind: PhoneTaskKind
    var command: String
    var slots: [PhoneSlot]
    var enabled: Bool
    var source: String? = nil
}

enum PhoneRunResult: String, Equatable {
    case success
    case unconfirmed
    case skipped
    case stopped
    case open
    case note
}

struct PhoneLogLine: Equatable, Identifiable {
    var date: Date
    var message: String
    var id: String { "\(date.timeIntervalSince1970)-\(message)" }
}

struct PhoneRun: Equatable, Identifiable {
    var id: String
    var lines: [PhoneLogLine]
    var result: PhoneRunResult
    var shift: PhoneTaskKind?

    var started: Date { lines[0].date }
}

struct PhoneRunCounts: Equatable {
    var success = 0
    var unconfirmed = 0
    var skipped = 0
    var stopped = 0
    var open = 0

    var total: Int { success + unconfirmed + skipped + stopped + open }
}

struct PhoneDesk: Equatable {
    var scriptReady: Bool
    var tasks: [PhoneTaskSnapshot]
    var runs: [PhoneRun]
    var savedProblem: String?
}

enum PhoneCheckoutResolve: Equatable {
    case ready(URL)
    case missingScript
    case notDirectory
}

protocol PhoneTaskLaunching {
    func bootout(label: String)
    func bootstrap(label: String, plist: URL) throws
    func isLoaded(label: String) -> Bool
}

enum PhoneUseLocation {
    static let punchInLabel = "com.iphone-use.punch-in"
    static let punchOutLabel = "com.iphone-use.punch-out"
    static let ownedPrefix = "com.macbj.phone-task."
    private static let checkoutKey = "macbj.phone.checkout"
    private static let introKey = "macbj.phone.introSeen"
    private static let checkoutOpenKey = "macbj.phone.checkoutOpen"
    private static let editorOpenKey = "macbj.phone.editorOpen"
    private static let logOpenKey = "macbj.phone.logOpen"
    private static let selectedTaskKey = "macbj.phone.selectedTask"

    static var checkout: URL {
        savedCheckout ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("macbj-iphone-use-missing", isDirectory: true)
    }

    static var savedCheckout: URL? {
        let raw = UserDefaults.standard.string(forKey: checkoutKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
    }

    static var introSeen: Bool {
        get { UserDefaults.standard.bool(forKey: introKey) }
        set { UserDefaults.standard.set(newValue, forKey: introKey) }
    }

    /// 脚本位置面板是否展开。没有存过时默认收起。
    static var checkoutOpen: Bool {
        get { UserDefaults.standard.bool(forKey: checkoutOpenKey) }
        set { UserDefaults.standard.set(newValue, forKey: checkoutOpenKey) }
    }

    static var editorOpen: Bool {
        get { UserDefaults.standard.bool(forKey: editorOpenKey) }
        set { UserDefaults.standard.set(newValue, forKey: editorOpenKey) }
    }

    static var logOpen: Bool {
        get { UserDefaults.standard.bool(forKey: logOpenKey) }
        set { UserDefaults.standard.set(newValue, forKey: logOpenKey) }
    }

    static var selectedTaskID: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: selectedTaskKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? nil : raw
        }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: selectedTaskKey)
            } else {
                UserDefaults.standard.removeObject(forKey: selectedTaskKey)
            }
        }
    }

    static func setCheckout(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: checkoutKey)
    }

    static func clearCheckout() {
        UserDefaults.standard.removeObject(forKey: checkoutKey)
    }

    /// 接受项目目录、`scripts` 目录，或 `scripts/punch.py` 本身。
    static func resolveCheckout(_ raw: String) -> PhoneCheckoutResolve {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notDirectory }
        let url = URL(fileURLWithPath: trimmed).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return .notDirectory }
        if !isDirectory.boolValue {
            guard url.lastPathComponent == "punch.py" else { return .notDirectory }
            let root = url.deletingLastPathComponent().deletingLastPathComponent()
            return scriptExists(root) ? .ready(root) : .missingScript
        }
        if scriptExists(url) { return .ready(url) }
        if url.lastPathComponent == "scripts", scriptExists(url.deletingLastPathComponent()) {
            return .ready(url.deletingLastPathComponent())
        }
        return .missingScript
    }

    private static func scriptExists(_ root: URL) -> Bool {
        FileManager.default.isFile(at: root.appendingPathComponent("scripts/punch.py"))
    }

    static var state: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/iphone-use", isDirectory: true)
    }

    static var agents: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    static var saved: URL { ToolboxPaths.file("phone-tasks.json") }

    static var script: URL { checkout.appendingPathComponent("scripts/punch.py") }

    static var punchLog: URL { state.appendingPathComponent("logs/punch.log") }
}

struct PhoneTaskSync: Equatable {
    var titles: [String]
    var problems: [String]

    var summary: String {
        var parts: [String] = []
        if !titles.isEmpty {
            parts.append(L("已按文件挂上：%@", titles.joined(separator: "、")))
        }
        parts.append(contentsOf: problems)
        return parts.joined(separator: " ")
    }
}

enum PhoneTaskFile {
    struct Document: Equatable {
        var source: String
        var title: String
        var note: String
        var kind: PhoneTaskKind
        var command: String
        var slots: [PhoneSlot]
    }

    enum Read: Equatable {
        case ready(Document)
        case problem(String)
    }

    static func isTaskName(_ name: String) -> Bool {
        guard name.hasSuffix(".task.json") else { return false }
        let stem = String(name.dropLast(".task.json".count))
        guard let first = stem.first, first.isLetter || first.isNumber else { return false }
        return stem.count <= 40 && stem.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    static func read(_ url: URL, checkout: URL) -> Read {
        let name = url.lastPathComponent
        guard isTaskName(name) else { return .problem(L("读不出定时文件 %@。", name)) }
        let stem = String(name.dropLast(".task.json".count))
        guard let data = try? Data(contentsOf: url),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .problem(L("读不出定时文件 %@。", name))
        }
        let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if title.isEmpty || title.count > 40 || title.contains(where: { $0 == "\n" || $0 == "\r" }) {
            return .problem(L("%@ 的名称不能用。", name))
        }
        let note = (body["note"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let kind = (body["kind"] as? String).flatMap(PhoneTaskKind.init(rawValue:)) else {
            return .problem(L("%@ 的任务类型不能用。", name))
        }
        guard let rawDays = body["weekdays"] as? [Any] else {
            return .problem(L("%@ 的星期或时间不能用。", name))
        }
        let days = rawDays.compactMap { jsonInt($0) }
        guard days.count == rawDays.count, !days.isEmpty,
              days.allSatisfy({ PhoneSlot.normalize(weekday: $0) != nil }),
              let hour = jsonInt(body["hour"]), (0...23).contains(hour),
              let minute = jsonInt(body["minute"]), (0...59).contains(minute) else {
            return .problem(L("%@ 的星期或时间不能用。", name))
        }
        let slots = days.compactMap { weekday -> PhoneSlot? in
            guard let weekday = PhoneSlot.normalize(weekday: weekday) else { return nil }
            return PhoneSlot(weekday: weekday, hour: hour, minute: minute)
        }.sorted {
            PhoneSlot.weekOrder.firstIndex(of: $0.weekday) ?? 0 < PhoneSlot.weekOrder.firstIndex(of: $1.weekday) ?? 0
        }
        let command: String
        if kind == .command {
            let script = "scripts/tasks/\(stem).py"
            guard body["script"] as? String == script else {
                return .problem(L("%@ 的脚本路径不对。", name))
            }
            let file = checkout
                .appendingPathComponent("scripts", isDirectory: true)
                .appendingPathComponent("tasks", isDirectory: true)
                .appendingPathComponent(stem + ".py")
            var directory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &directory), !directory.boolValue else {
                return .problem(L("%@ 还没有旁边的脚本。", name))
            }
            command = "python3 \(script)"
        } else {
            command = ""
        }
        return .ready(Document(source: name, title: title, note: note, kind: kind, command: command, slots: slots))
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.intValue
    }
}

enum PhoneTasks {
    static func desk(
        checkout: URL = PhoneUseLocation.checkout,
        state: URL = PhoneUseLocation.state,
        agents: URL = PhoneUseLocation.agents,
        saved: URL = PhoneUseLocation.saved,
        launch: any PhoneTaskLaunching
    ) -> PhoneDesk {
        let script = checkout.appendingPathComponent("scripts/punch.py")
        let scriptReady = FileManager.default.isFile(at: script)
        let logText = (try? String(contentsOf: state.appendingPathComponent("logs/punch.log"), encoding: .utf8)) ?? ""
        let savedRead = readSaved(saved)
        var tasks = builtinTasks(agents: agents, launch: launch)
        if case .tasks(let owned) = savedRead {
            tasks.append(contentsOf: owned.map { snapshot($0, agents: agents, launch: launch) })
        }
        return PhoneDesk(
            scriptReady: scriptReady,
            tasks: tasks,
            runs: PhoneLog.parse(logText),
            savedProblem: savedRead.problem
        )
    }

    static func add(
        _ draft: PhoneTaskDraft,
        checkout: URL,
        state: URL,
        agents: URL,
        saved: URL,
        launch: any PhoneTaskLaunching
    ) throws -> (id: String, warning: String?) {
        if let problem = draft.problem(scriptReady: FileManager.default.isFile(at: checkout.appendingPathComponent("scripts/punch.py"))) {
            throw ToolError(problem)
        }
        var tasks = savedTasks(saved)
        let task = SavedPhoneTask(
            id: UUID().uuidString.lowercased(),
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: draft.kind,
            command: draft.command.trimmingCharacters(in: .whitespacesAndNewlines),
            slots: draft.slots,
            enabled: true
        )
        tasks.append(task)
        try write(tasks, to: saved)
        do {
            try publish(task, checkout: checkout, state: state, agents: agents, launch: launch)
        } catch {
            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[index].enabled = false
                try? write(tasks, to: saved)
            }
            let text = (error as? ToolError)?.text ?? error.localizedDescription
            return (task.id, text.isEmpty ? L("定时没有挂上。") : text)
        }
        return (task.id, nil)
    }

    /// 读取 `scripts/tasks/*.task.json`。新文件挂上定时，改过的文件更新定时，文件没了就卸下。
    static func syncTaskFiles(
        checkout: URL,
        state: URL,
        agents: URL,
        saved: URL,
        launch: any PhoneTaskLaunching
    ) -> PhoneTaskSync {
        guard FileManager.default.isFile(at: checkout.appendingPathComponent("scripts/punch.py")) else {
            return PhoneTaskSync(titles: [], problems: [])
        }
        let folder = checkout
            .appendingPathComponent("scripts", isDirectory: true)
            .appendingPathComponent("tasks", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .map(\.lastPathComponent)
            .filter { PhoneTaskFile.isTaskName($0) }
            .sorted() ?? []
        var tasks = savedTasks(saved)
        var titles: [String] = []
        var problems: [String] = []
        var seen: Set<String> = []
        for name in names {
            let url = folder.appendingPathComponent(name)
            switch PhoneTaskFile.read(url, checkout: checkout) {
            case .ready(let document):
                seen.insert(document.source)
                if let index = tasks.firstIndex(where: { $0.source == document.source }) {
                    if tasks[index].title != document.title
                        || tasks[index].note != document.note
                        || tasks[index].kind != document.kind
                        || tasks[index].command != document.command
                        || tasks[index].slots != document.slots {
                        tasks[index].title = document.title
                        tasks[index].note = document.note
                        tasks[index].kind = document.kind
                        tasks[index].command = document.command
                        tasks[index].slots = document.slots
                        titles.append(document.title)
                        if tasks[index].enabled {
                            do {
                                try publish(tasks[index], checkout: checkout, state: state, agents: agents, launch: launch)
                            } catch {
                                tasks[index].enabled = false
                                let text = (error as? ToolError)?.text ?? error.localizedDescription
                                problems.append(text.isEmpty ? L("定时没有挂上。") : text)
                            }
                        }
                    }
                } else {
                    var task = SavedPhoneTask(
                        id: UUID().uuidString.lowercased(),
                        title: document.title,
                        note: document.note,
                        kind: document.kind,
                        command: document.command,
                        slots: document.slots,
                        enabled: true,
                        source: document.source
                    )
                    do {
                        try publish(task, checkout: checkout, state: state, agents: agents, launch: launch)
                    } catch {
                        task.enabled = false
                        let text = (error as? ToolError)?.text ?? error.localizedDescription
                        problems.append(text.isEmpty ? L("定时没有挂上。") : text)
                    }
                    tasks.append(task)
                    titles.append(document.title)
                }
            case .problem(let text):
                problems.append(text)
            }
        }
        let stale = tasks.filter { task in
            guard let source = task.source else { return false }
            return !seen.contains(source)
        }
        for task in stale {
            if let label = ownedLabel(task.id) {
                launch.bootout(label: label)
                let plist = agents.appendingPathComponent(label + ".plist")
                if FileManager.default.fileExists(atPath: plist.path) {
                    try? FileManager.default.removeItem(at: plist)
                }
            }
        }
        if !stale.isEmpty {
            tasks.removeAll { task in
                guard let source = task.source else { return false }
                return !seen.contains(source)
            }
        }
        if !titles.isEmpty || !stale.isEmpty {
            try? write(tasks, to: saved)
        }
        return PhoneTaskSync(titles: titles, problems: problems)
    }

    static func setEnabled(
        id: String,
        enabled: Bool,
        checkout: URL,
        state: URL,
        agents: URL,
        saved: URL,
        launch: any PhoneTaskLaunching
    ) throws {
        guard let label = ownedLabel(id) else { throw ToolError(L("没有这个定时。")) }
        var tasks = savedTasks(saved)
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { throw ToolError(L("没有这个定时。")) }
        tasks[index].enabled = enabled
        try write(tasks, to: saved)
        if enabled {
            do {
                try publish(tasks[index], checkout: checkout, state: state, agents: agents, launch: launch)
            } catch {
                tasks[index].enabled = false
                try? write(tasks, to: saved)
                throw error
            }
        } else {
            launch.bootout(label: label)
        }
    }

    static func remove(
        id: String,
        agents: URL,
        saved: URL,
        launch: any PhoneTaskLaunching
    ) throws {
        guard let label = ownedLabel(id) else { throw ToolError(L("没有这个定时。")) }
        launch.bootout(label: label)
        let plist = agents.appendingPathComponent(label + ".plist")
        if FileManager.default.fileExists(atPath: plist.path) {
            try FileManager.default.removeItem(at: plist)
        }
        var tasks = savedTasks(saved)
        guard tasks.contains(where: { $0.id == id }) else { throw ToolError(L("没有这个定时。")) }
        tasks.removeAll { $0.id == id }
        try write(tasks, to: saved)
    }

    static func attachBuiltin(label: String, agents: URL, launch: any PhoneTaskLaunching) throws {
        guard label == PhoneUseLocation.punchInLabel || label == PhoneUseLocation.punchOutLabel else {
            throw ToolError(L("没有这个定时。"))
        }
        let plist = agents.appendingPathComponent(label + ".plist")
        guard FileManager.default.isFile(at: plist) else { throw ToolError(L("没有定时文件。")) }
        try launch.bootstrap(label: label, plist: plist)
    }

    /// 立刻执行时，命令按 shell 语句跑。整段加引号会让 zsh 把 `python3 scripts/...py` 当成一个文件名。
    static func commandShell(command: String, checkout: URL) -> String {
        "cd \(ShellLiteral.singleQuoted(checkout.path)) && \(command)"
    }

    static func overlaps(_ draft: PhoneTaskDraft, tasks: [PhoneTaskSnapshot]) -> Bool {
        let incoming = Set(draft.slots.map(\.id))
        return tasks.contains { task in
            guard task.kind == draft.kind, draft.kind != .command else { return false }
            return task.slots.contains { incoming.contains($0.id) }
        }
    }

    static func scheduleText(_ slots: [PhoneSlot]) -> String {
        let groups = Dictionary(grouping: slots, by: { String(format: "%02d:%02d", $0.hour, $0.minute) })
        return groups.keys.sorted().map { time in
            let days = (groups[time] ?? []).sorted {
                PhoneSlot.weekOrder.firstIndex(of: $0.weekday) ?? 0 < PhoneSlot.weekOrder.firstIndex(of: $1.weekday) ?? 0
            }.map { weekdayName($0.weekday) }
            return days.joined(separator: "、") + " " + time
        }.joined(separator: "  ")
    }

    static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: L("周一")
        case 2: L("周二")
        case 3: L("周三")
        case 4: L("周四")
        case 5: L("周五")
        case 6: L("周六")
        default: L("周日")
        }
    }

    /// `--now` 的成功行不带上班、下班。只把它算到这次亲手执行的任务上。
    static func matchedRun(kind: PhoneTaskKind, runs: [PhoneRun], since: Date?) -> PhoneRun? {
        if let since {
            let fresh = runs.last { run in
                guard run.shift == nil, let end = run.lines.last?.date, end >= since.addingTimeInterval(-2) else { return false }
                switch run.result {
                case .success, .unconfirmed, .stopped: return true
                case .skipped, .open, .note: return false
                }
            }
            if let fresh { return fresh }
        }
        return runs.last { $0.shift == kind }
    }

    static func counts(_ runs: [PhoneRun]) -> PhoneRunCounts {
        runs.reduce(into: PhoneRunCounts()) { counts, run in
            switch run.result {
            case .success: counts.success += 1
            case .unconfirmed: counts.unconfirmed += 1
            case .skipped: counts.skipped += 1
            case .stopped: counts.stopped += 1
            case .open: counts.open += 1
            case .note: break
            }
        }
    }

    private static func builtinTasks(agents: URL, launch: any PhoneTaskLaunching) -> [PhoneTaskSnapshot] {
        [
            (PhoneUseLocation.punchInLabel, PhoneTaskKind.punchIn, L("上班打卡")),
            (PhoneUseLocation.punchOutLabel, PhoneTaskKind.punchOut, L("下班打卡")),
        ].map { label, kind, title in
            let plist = agents.appendingPathComponent(label + ".plist")
            let parsed = (try? Data(contentsOf: plist)).flatMap { taskBody(from: $0) }
            return PhoneTaskSnapshot(
                id: label,
                title: title,
                note: L("工作日到点后，脚本在窗口内随机等一会儿，再打开飞书假勤。两个杭州读云账号里，这一班还没打卡才点。"),
                kind: kind,
                command: "",
                slots: parsed?.slots ?? [],
                enabled: parsed != nil,
                owned: false,
                loaded: launch.isLoaded(label: label),
                agent: FileManager.default.isFile(at: plist) ? plist : nil,
                source: nil
            )
        }
    }

    private static func snapshot(_ task: SavedPhoneTask, agents: URL, launch: any PhoneTaskLaunching) -> PhoneTaskSnapshot {
        let label = ownedLabel(task.id) ?? task.id
        let note = task.kind == .command
            ? task.note
            : [task.note, L("到了所选的分钟会立刻打卡，不再等脚本里原来的时间窗口。")]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        return PhoneTaskSnapshot(
            id: task.id,
            title: task.title,
            note: note,
            kind: task.kind,
            command: task.command,
            slots: task.slots,
            enabled: task.enabled,
            owned: true,
            loaded: task.enabled && launch.isLoaded(label: label),
            agent: agents.appendingPathComponent(label + ".plist"),
            source: task.source
        )
    }

    private static func publish(
        _ task: SavedPhoneTask,
        checkout: URL,
        state: URL,
        agents: URL,
        launch: any PhoneTaskLaunching
    ) throws {
        guard let label = ownedLabel(task.id) else { throw ToolError(L("没有这个定时。")) }
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = agents.appendingPathComponent(label + ".plist")
        let body = try plistData(task, label: label, checkout: checkout, state: state, agents: agents)
        try body.write(to: plist, options: .atomic)
        launch.bootout(label: label)
        try launch.bootstrap(label: label, plist: plist)
    }

    static func plistData(_ task: SavedPhoneTask, label: String, checkout: URL, state: URL, agents: URL) throws -> Data {
        let python = pythonExecutable(agents: agents)
        let script = checkout.appendingPathComponent("scripts/punch.py").path
        let arguments: [String]
        switch task.kind {
        case .punchIn:
            arguments = [python, script, "in", "--now"]
        case .punchOut:
            arguments = [python, script, "out", "--now"]
        case .command:
            arguments = ["/bin/zsh", "-lc", task.command]
        }
        var body: [String: Any] = [
            "Label": label,
            "ProgramArguments": arguments,
            "StartCalendarInterval": task.slots.map {
                ["Weekday": $0.weekday, "Hour": $0.hour, "Minute": $0.minute] as [String: Any]
            },
            "EnvironmentVariables": [
                "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                "PATH": pathEnvironment(agents: agents),
            ],
            "StandardOutPath": state.appendingPathComponent("logs/\(label).log").path,
            "StandardErrorPath": state.appendingPathComponent("logs/\(label).log").path,
        ]
        if task.kind == .command {
            body["WorkingDirectory"] = checkout.path
        }
        return try PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
    }

    static func taskBody(from data: Data) -> (slots: [PhoneSlot], arguments: [String])? {
        guard let body = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        let arguments = body["ProgramArguments"] as? [String] ?? []
        let slots = slots(from: body["StartCalendarInterval"])
        return (slots, arguments)
    }

    static func ownedLabel(_ id: String) -> String? {
        guard !id.isEmpty, id.count <= 40, id.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
        return PhoneUseLocation.ownedPrefix + id
    }

    private static func slots(from value: Any?) -> [PhoneSlot] {
        let rows: [[String: Any]]
        if let one = value as? [String: Any] {
            rows = [one]
        } else if let many = value as? [[String: Any]] {
            rows = many
        } else {
            rows = []
        }
        return rows.compactMap { row in
            guard let weekday = (row["Weekday"] as? Int).flatMap(PhoneSlot.normalize(weekday:)),
                  let hour = row["Hour"] as? Int, (0...23).contains(hour),
                  let minute = row["Minute"] as? Int, (0...59).contains(minute) else { return nil }
            return PhoneSlot(weekday: weekday, hour: hour, minute: minute)
        }
    }

    static func pythonExecutable(agents: URL) -> String {
        for label in [PhoneUseLocation.punchInLabel, PhoneUseLocation.punchOutLabel] {
            let plist = agents.appendingPathComponent(label + ".plist")
            if let arguments = (try? Data(contentsOf: plist)).flatMap({ taskBody(from: $0)?.arguments }),
               let python = arguments.first, FileManager.default.isExecutableFile(atPath: python) {
                return python
            }
        }
        return "/usr/bin/python3"
    }

    private static func pathEnvironment(agents: URL) -> String {
        for label in [PhoneUseLocation.punchInLabel, PhoneUseLocation.punchOutLabel] {
            let plist = agents.appendingPathComponent(label + ".plist")
            guard let data = try? Data(contentsOf: plist),
                  let body = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let environment = body["EnvironmentVariables"] as? [String: String],
                  let path = environment["PATH"], !path.isEmpty else { continue }
            return path
        }
        return "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    }

    private static func savedTasks(_ url: URL) -> [SavedPhoneTask] {
        if case .tasks(let tasks) = readSaved(url) { return tasks }
        return []
    }

    private static func readSaved(_ url: URL) -> SavedRead {
        guard FileManager.default.isFile(at: url) else { return .tasks([]) }
        do {
            let data = try Data(contentsOf: url)
            return .tasks(try JSONDecoder().decode([SavedPhoneTask].self, from: data))
        } catch {
            return .broken(L("定时清单读不出来。"))
        }
    }

    private static func write(_ tasks: [SavedPhoneTask], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(tasks)
        try data.write(to: url, options: .atomic)
    }
}

private enum SavedRead {
    case tasks([SavedPhoneTask])
    case broken(String)

    var problem: String? {
        if case .broken(let text) = self { return text }
        return nil
    }
}

enum PhoneLog {
    private static let gap: TimeInterval = 120

    static func parse(_ text: String) -> [PhoneRun] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let raw = text.split(separator: "\n", omittingEmptySubsequences: false).suffix(2000)
        var lines: [PhoneLogLine] = []
        for rawLine in raw {
            let line = String(rawLine)
            guard line.count >= 20 else { continue }
            let stamp = String(line.prefix(19))
            guard line.dropFirst(19).first == " ", let date = formatter.date(from: stamp) else { continue }
            lines.append(PhoneLogLine(date: date, message: String(line.dropFirst(20))))
        }
        var runs: [PhoneRun] = []
        var current: [PhoneLogLine] = []
        func close() {
            guard !current.isEmpty else { return }
            let index = runs.count
            let messages = current.map(\.message)
            runs.append(PhoneRun(
                id: "\(index)-\(current[0].date.timeIntervalSince1970)",
                lines: current,
                result: result(of: messages),
                shift: shift(of: messages)
            ))
            current = []
        }
        for line in lines {
            if let previous = current.last {
                let delta = line.date.timeIntervalSince(previous.date)
                if delta > gap || delta < 0 { close() }
            }
            current.append(line)
            if isTerminal(line.message) { close() }
        }
        close()
        return runs
    }

    static func excerpt(after date: Date, in text: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let floor = date.addingTimeInterval(-2)
        return text.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw -> String? in
            let line = String(raw)
            guard line.count >= 20 else { return nil }
            let stamp = String(line.prefix(19))
            guard line.dropFirst(19).first == " ", let parsed = formatter.date(from: stamp), parsed >= floor else { return nil }
            return line
        }.joined(separator: "\n")
    }

    static func result(of messages: [String]) -> PhoneRunResult {
        if messages.contains(where: { $0.contains("打卡未确认") }) { return .unconfirmed }
        if messages.contains(where: { $0.contains("打卡成功") }) { return .success }
        if messages.contains(where: { $0.hasPrefix("stopped:") }) { return .stopped }
        if messages.contains(where: { $0.hasPrefix("skip ") }) { return .skipped }
        if messages.contains(where: { $0.hasPrefix("installed ") || $0.hasPrefix("switch ") }) { return .note }
        return .open
    }

    static func shift(of messages: [String]) -> PhoneTaskKind? {
        for message in messages {
            if message.contains("上班") || message.contains("skip in") { return .punchIn }
            if message.contains("下班") || message.contains("skip out") { return .punchOut }
        }
        return nil
    }

    private static func isTerminal(_ message: String) -> Bool {
        message.hasPrefix("installed ")
            || message.hasPrefix("skip ")
            || message.hasPrefix("stopped:")
            || message.hasPrefix("switch ")
            || message.contains("打卡未确认")
            || message.contains("打卡成功")
    }
}

struct SystemPhoneTaskLaunch: PhoneTaskLaunching {
    func bootout(label: String) {
        _ = Self.run(["bootout", "gui/\(getuid())/\(label)"])
    }

    func bootstrap(label: String, plist: URL) throws {
        let result = Self.run(["bootstrap", "gui/\(getuid())", plist.path])
        if result.status != 0 {
            let text = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(text.isEmpty ? L("定时没有挂上。") : text)
        }
    }

    func isLoaded(label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "gui/\(getuid())/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func run(_ arguments: [String]) -> (status: Int32, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe
        do { try process.run() } catch {
            return (1, error.localizedDescription)
        }
        process.waitUntilExit()
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, stderr)
    }
}

private extension FileManager {
    func isFile(at url: URL) -> Bool {
        var directory: ObjCBool = false
        return fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
    }
}
