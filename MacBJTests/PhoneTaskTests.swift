import Foundation
import Testing
@testable import MacBJ

struct PhoneTaskTests {
    @Test("punch log splits into results")
    func punchLogSplitsIntoResults() {
        let text = """
        2026-11-13 14:07:35 installed com.iphone-use.punch-in
        2026-11-13 14:07:35 installed com.iphone-use.punch-out
        2026-11-13 14:09:35 opened 假勤 at (212, 393)
        2026-11-13 14:09:39 tapped punch-button at (196, 468)
        2026-11-13 14:09:54 打卡未确认 /tmp/a.jpg
        2026-11-13 14:12:07 opened 假勤 at (212, 393)
        2026-11-13 14:12:17 page not-ready
        2026-11-13 14:27:29 ocr 吴建民
        2026-11-13 14:27:49 switch 吴建民 -> 陈家斌 -> 吴建民
        2026-11-13 15:00:10 opened pinned 假勤 at (1, 2)
        2026-11-13 15:00:40 上班打卡成功 吴建民 /tmp/b.jpg
        2026-11-14 08:55:01 skip in: weekend
        2026-11-14 18:02:01 skip out: outside-window
        2026-11-14 18:10:00 stopped: phone-locked
        """
        let runs = PhoneLog.parse(text)
        #expect(runs.map(\.result) == [.note, .note, .unconfirmed, .open, .note, .success, .skipped, .skipped, .stopped])
        #expect(runs[2].shift == nil)
        #expect(runs[5].shift == .punchIn)
        #expect(runs[6].shift == .punchIn)
        #expect(runs[7].shift == .punchOut)
        let counts = PhoneTasks.counts(runs)
        #expect(counts.success == 1)
        #expect(counts.unconfirmed == 1)
        #expect(counts.skipped == 2)
        #expect(counts.stopped == 1)
        #expect(counts.open == 1)
        #expect(counts.total == 6)
    }

    @Test("a new schedule needs a name, a day, and a real time")
    func aNewScheduleNeedsANameADayAndARealTime() {
        var draft = PhoneTaskDraft(title: "  ", note: "", kind: .punchIn, command: "", weekdays: [1], hour: 9, minute: 0)
        #expect(draft.problem(scriptReady: true) == L("先写名称。"))
        draft.title = "早班\n打卡"
        #expect(draft.problem(scriptReady: true) == L("名称不能换行。"))
        draft.title = "早班"
        draft.weekdays = []
        #expect(draft.problem(scriptReady: true) == L("至少选一个星期。"))
        draft.weekdays = [1, 5]
        draft.hour = 24
        #expect(draft.problem(scriptReady: true) == L("时间要在 0:00 到 23:59。"))
        draft.hour = 9
        #expect(draft.problem(scriptReady: false) == L("没有找到打卡脚本。"))
        draft.kind = .command
        draft.command = "echo hi\necho no"
        #expect(draft.problem(scriptReady: false) == L("命令不能换行。"))
        draft.command = "python3 scripts/phone.py pua_ready '{}'"
        #expect(draft.problem(scriptReady: false) == nil)
        #expect(draft.slots.map(\.weekday) == [1, 5])
    }

    @Test("an AI brief names the script the schedule will run")
    func anAIBriefNamesTheScriptTheScheduleWillRun() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let checkout = root.appendingPathComponent("iPhone-use", isDirectory: true)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        let punch = checkout.appendingPathComponent("scripts/punch.py")
        try Data("print(1)\n".utf8).write(to: punch)
        #expect(PhoneTaskBrief.slug(title: "补卡") == PhoneTaskBrief.slug(title: "补卡"))
        #expect(PhoneTaskBrief.slug(title: "补卡") != PhoneTaskBrief.slug(title: "下班"))
        #expect(PhoneTaskBrief.slug(title: "补卡").hasPrefix("task-"))
        #expect(PhoneTaskBrief.slug(title: "Morning Run").hasPrefix("morningrun-"))
        let written = try PhoneTaskBrief.write(
            title: "补卡",
            note: "打开备忘录看第一条",
            schedule: "周一 09:05",
            checkout: checkout,
            kind: .command,
            weekdays: [1],
            hour: 9,
            minute: 5
        )
        let relative = "scripts/tasks/\(written.slug).py"
        #expect(written.command == "python3 \(relative)")
        #expect(!written.command.contains("\n"))
        #expect(written.markdown.contains(checkout.path))
        #expect(written.markdown.contains(relative))
        #expect(written.markdown.contains("scripts/punch.py"))
        #expect(written.markdown.contains("stopped: phone-locked"))
        #expect(written.markdown.contains("不要运行 sh scripts/install.sh"))
        #expect(PhoneTaskBrief.installPrompt(.codex).contains("sh scripts/install.sh"))
        #expect(PhoneTaskBrief.installPrompt(.workBuddy).contains("python3 workbuddy/install.py"))
        #expect(PhoneTaskBrief.installPrompt(.workBuddy).contains("不要运行 Codex 安装脚本"))
        #expect(PhoneTaskBrief.installPrompt(.doubao).contains("python3 doubao/install.py"))
        #expect(PhoneTaskBrief.installPrompt(.grok).contains("不要编造 Grok 的 install.py"))
        for host in [PhoneAIHost.muse, .claudeCode, .openCode, .cursor, .deepSeek] {
            let install = PhoneTaskBrief.installPrompt(host)
            #expect(install.contains("\(host.title) 没有单独的安装器"))
            #expect(install.contains("不要编造 \(host.title) 的 install.py"))
            let task = PhoneTaskBrief.taskPrompt(host: host, title: "补卡", note: "打开备忘录看第一条", schedule: "周一 09:05", rootPath: checkout.path, slug: written.slug, kind: .command, weekdays: [1], hour: 9, minute: 5)
            #expect(task.contains(host.title))
            #expect(task.contains("不要运行 sh scripts/install.sh"))
        }
        #expect(written.markdown.contains("这次定时要做的事"))
        #expect(written.markdown.contains("打开备忘录看第一条"))
        #expect(PhoneTaskBrief.action(kind: .punchIn, note: "").contains("上班打卡"))
        #expect(PhoneTaskBrief.action(kind: .command, note: "  打开备忘录  ") == "打开备忘录")
        #expect(PhoneTaskBrief.action(kind: .command, note: "  ") == "")
        #expect(written.markdown.contains("点刷新"))
        #expect(written.markdown.contains(".task.json"))
        let buddy = PhoneTaskBrief.taskPrompt(
            host: .workBuddy,
            title: "补卡",
            note: "打开备忘录看第一条",
            schedule: "周一 09:05",
            rootPath: checkout.path,
            slug: written.slug,
            kind: .command,
            weekdays: [1],
            hour: 9,
            minute: 5
        )
        #expect(buddy.contains("不要运行 Codex 安装脚本"))
        #expect(buddy.contains("打开备忘录看第一条"))
        #expect(!written.scriptExists)
        let saved = try String(contentsOf: written.file, encoding: .utf8)
        #expect(saved == written.markdown)
        let punchAfter = try String(contentsOf: punch, encoding: .utf8)
        #expect(punchAfter == "print(1)\n")
        #expect(PhoneTaskBrief.missingScript(command: written.command, checkout: checkout) == relative)
        try Data("print(2)\n".utf8).write(to: checkout.appendingPathComponent("scripts").appendingPathComponent("tasks").appendingPathComponent("\(written.slug).py"))
        #expect(PhoneTaskBrief.missingScript(command: written.command, checkout: checkout) == nil)
    }

    @Test("a saved task file becomes a schedule and leaving removes it")
    func aSavedTaskFileBecomesAScheduleAndLeavingRemovesIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let checkout = root.appendingPathComponent("iPhone-use", isDirectory: true)
        let agents = root.appendingPathComponent("agents", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        let saved = root.appendingPathComponent("phone-tasks.json")
        let folder = checkout.appendingPathComponent("scripts").appendingPathComponent("tasks")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("print(1)\n".utf8).write(to: checkout.appendingPathComponent("scripts").appendingPathComponent("punch.py"))
        try Data("print(1)\n".utf8).write(to: folder.appendingPathComponent("demo.py"))
        let launch = MemoryPhoneLaunch()
        let manual = PhoneTaskDraft(title: "手动", note: "", kind: .punchIn, command: "", weekdays: [1], hour: 8, minute: 0)
        _ = try PhoneTasks.add(manual, checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        let json = PhoneTaskBrief.taskFileJSON(title: "补卡", note: "看备忘录", kind: .command, slug: "demo", weekdays: [1, 3], hour: 9, minute: 5)
        try Data(json.utf8).write(to: folder.appendingPathComponent("demo.task.json"))
        let first = PhoneTasks.syncTaskFiles(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(first.titles == ["补卡"])
        var desk = PhoneTasks.desk(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        let adopted = try #require(desk.tasks.first { $0.source == "demo.task.json" })
        #expect(PhoneTasks.commandShell(command: "python3 scripts/tasks/task-f64660ef.py", checkout: checkout) == "cd \(ShellLiteral.singleQuoted(checkout.path)) && python3 scripts/tasks/task-f64660ef.py")
        #expect(adopted.slots.map(\.weekday) == [1, 3])
        #expect(adopted.slots[0].hour == 9)
        #expect(desk.tasks.contains { $0.title == "手动" && $0.source == nil })
        let again = PhoneTasks.syncTaskFiles(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(again.titles.isEmpty)
        let moved = PhoneTaskBrief.taskFileJSON(title: "补卡", note: "看备忘录", kind: .command, slug: "demo", weekdays: [1, 3], hour: 10, minute: 5)
        try Data(moved.utf8).write(to: folder.appendingPathComponent("demo.task.json"))
        let updated = PhoneTasks.syncTaskFiles(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(updated.titles == ["补卡"])
        desk = PhoneTasks.desk(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(desk.tasks.first { $0.source == "demo.task.json" }?.slots[0].hour == 10)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("demo.task.json"))
        _ = PhoneTasks.syncTaskFiles(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        desk = PhoneTasks.desk(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(!desk.tasks.contains { $0.source == "demo.task.json" })
        #expect(desk.tasks.contains { $0.title == "手动" })
        let missing = PhoneTaskBrief.taskFileJSON(title: "缺脚本", note: "", kind: .command, slug: "other", weekdays: [2], hour: 9, minute: 0)
        try Data(missing.utf8).write(to: folder.appendingPathComponent("other.task.json"))
        let problem = PhoneTasks.syncTaskFiles(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(problem.problems.contains { $0.contains("other.task.json") })
        #expect(!PhoneTasks.desk(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch).tasks.contains { $0.title == "缺脚本" })
    }

    @Test("adding a task writes a launch agent and removing it takes the agent down")
    func addingATaskWritesALaunchAgentAndRemovingItTakesTheAgentDown() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let checkout = root.appendingPathComponent("iPhone-use", isDirectory: true)
        let agents = root.appendingPathComponent("agents", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        let saved = root.appendingPathComponent("phone-tasks.json")
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data().write(to: checkout.appendingPathComponent("scripts/punch.py"))
        let launch = MemoryPhoneLaunch()
        let draft = PhoneTaskDraft(title: "补卡", note: "迟到时用", kind: .punchIn, command: "", weekdays: [1, 2], hour: 9, minute: 5)
        try PhoneTasks.add(draft, checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        let desk = PhoneTasks.desk(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        let owned = try #require(desk.tasks.first { $0.owned })
        #expect(owned.title == "补卡")
        #expect(owned.loaded)
        #expect(owned.slots.map(\.weekday) == [1, 2])
        let plist = try Data(contentsOf: agents.appendingPathComponent(PhoneTasks.ownedLabel(owned.id)! + ".plist"))
        let body = try #require(PhoneTasks.taskBody(from: plist))
        #expect(Array(body.arguments.suffix(2)) == ["in", "--now"])
        #expect(body.slots.count == 2)
        #expect(PhoneTasks.overlaps(draft, tasks: desk.tasks))
        try PhoneTasks.remove(id: owned.id, agents: agents, saved: saved, launch: launch)
        #expect(launch.bootouts.contains(PhoneTasks.ownedLabel(owned.id)!))
        #expect(!FileManager.default.fileExists(atPath: agents.appendingPathComponent(PhoneTasks.ownedLabel(owned.id)! + ".plist").path))
        let after = PhoneTasks.desk(checkout: checkout, state: state, agents: agents, saved: saved, launch: launch)
        #expect(!after.tasks.contains { $0.owned })
    }

    @Test("an existing punch agent is shown and not treated as one we added")
    func anExistingPunchAgentIsShownAndNotTreatedAsOneWeAdded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let agents = root.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>com.iphone-use.punch-in</string>
        <key>ProgramArguments</key><array><string>/usr/bin/python3</string><string>/tmp/punch.py</string><string>in</string></array>
        <key>StartCalendarInterval</key><array>
        <dict><key>Weekday</key><integer>1</integer><key>Hour</key><integer>8</integer><key>Minute</key><integer>55</integer></dict>
        </array>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: agents.appendingPathComponent("com.iphone-use.punch-in.plist"))
        let launch = MemoryPhoneLaunch()
        launch.loaded = [PhoneUseLocation.punchInLabel]
        let desk = PhoneTasks.desk(
            checkout: root,
            state: root,
            agents: agents,
            saved: root.appendingPathComponent("missing.json"),
            launch: launch
        )
        let task = try #require(desk.tasks.first { $0.id == PhoneUseLocation.punchInLabel })
        #expect(!task.owned)
        #expect(task.loaded)
        #expect(task.slots == [PhoneSlot(weekday: 1, hour: 8, minute: 55)])
        #expect(PhoneTasks.scheduleText(task.slots) == L("周一") + " 08:55")
        #expect(throws: ToolError.self) {
            try PhoneTasks.remove(id: task.id, agents: agents, saved: root.appendingPathComponent("missing.json"), launch: launch)
        }
    }

    @Test("a schedule stays when the system timer does not load")
    func aScheduleStaysWhenTheSystemTimerDoesNotLoad() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let checkout = root.appendingPathComponent("iPhone-use", isDirectory: true)
        let agents = root.appendingPathComponent("agents", isDirectory: true)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try Data().write(to: checkout.appendingPathComponent("scripts/punch.py"))
        let saved = root.appendingPathComponent("phone-tasks.json")
        let draft = PhoneTaskDraft(title: "补一次", note: "", kind: .punchOut, command: "", weekdays: [3], hour: 18, minute: 5)
        let added = try PhoneTasks.add(draft, checkout: checkout, state: root, agents: agents, saved: saved, launch: RejectingPhoneLaunch())
        #expect(added.warning == L("定时没有挂上。"))
        let desk = PhoneTasks.desk(checkout: checkout, state: root, agents: agents, saved: saved, launch: RejectingPhoneLaunch())
        let owned = try #require(desk.tasks.first { $0.id == added.id })
        #expect(owned.enabled == false)
        #expect(owned.loaded == false)
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let runs = PhoneLog.parse("2026-11-13 14:09:54 打卡未确认 吴建民 /tmp/a.jpg\n")
        #expect(PhoneTasks.matchedRun(kind: .punchIn, runs: runs, since: nil) == nil)
        #expect(PhoneTasks.matchedRun(kind: .punchIn, runs: runs, since: runs[0].lines[0].date)?.result == .unconfirmed)
        let excerpt = PhoneLog.excerpt(after: since, in: "2023-01-01 00:00:00 old\n2026-11-13 14:09:54 打卡未确认 吴建民\n")
        #expect(excerpt.contains("打卡未确认"))
        #expect(!excerpt.contains("old"))
        try? FileManager.default.removeItem(at: root)
    }

    @Test("the script location can be the project, its scripts folder, or punch.py")
    func theScriptLocationCanBeTheProjectItsScriptsFolderOrPunchPy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).standardizedFileURL
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        let punch = scripts.appendingPathComponent("punch.py")
        try Data("print(1)\n".utf8).write(to: punch)
        guard case .ready(let project) = PhoneUseLocation.resolveCheckout(root.path) else {
            Issue.record("project directory")
            return
        }
        #expect(project.path == root.path)
        guard case .ready(let fromScripts) = PhoneUseLocation.resolveCheckout(scripts.path) else {
            Issue.record("scripts directory")
            return
        }
        #expect(fromScripts.path == root.path)
        guard case .ready(let fromFile) = PhoneUseLocation.resolveCheckout(punch.path) else {
            Issue.record("punch.py")
            return
        }
        #expect(fromFile.path == root.path)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(PhoneUseLocation.resolveCheckout(empty.path) == .missingScript)
        #expect(PhoneUseLocation.resolveCheckout(root.appendingPathComponent("missing").path) == .notDirectory)
        try? FileManager.default.removeItem(at: root)
    }
}

private final class MemoryPhoneLaunch: PhoneTaskLaunching {
    var loaded: Set<String> = []
    var bootouts: [String] = []

    func bootout(label: String) {
        bootouts.append(label)
        loaded.remove(label)
    }

    func bootstrap(label: String, plist: URL) throws {
        if !FileManager.default.fileExists(atPath: plist.path) {
            throw ToolError(L("定时没有挂上。"))
        }
        loaded.insert(label)
    }

    func isLoaded(label: String) -> Bool {
        loaded.contains(label)
    }
}

private final class RejectingPhoneLaunch: PhoneTaskLaunching {
    func bootout(label: String) {}

    func bootstrap(label: String, plist: URL) throws {
        throw ToolError(L("定时没有挂上。"))
    }

    func isLoaded(label: String) -> Bool { false }
}
