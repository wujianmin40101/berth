import Foundation

struct PortUse: Identifiable, Equatable, Sendable {
    var command: String
    var pid: Int32
    var address: String
    var port: Int
    var canStop: Bool = true

    var id: String { "\(pid):\(address)" }
}

enum PortListing {
    static func parse(_ text: String) -> [PortUse] {
        var command = ""
        var pid: Int32 = 0
        var rows: [PortUse] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p":
                pid = Int32(value) ?? 0
                command = ""
            case "c":
                command = value
            case "n":
                guard pid > 1, let port = port(in: value) else { continue }
                rows.append(PortUse(command: command.isEmpty ? L("未知进程") : command, pid: pid, address: value, port: port))
            default:
                continue
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.port != rhs.port { return lhs.port < rhs.port }
            return lhs.pid < rhs.pid
        }
    }

    static func port(in address: String) -> Int? {
        guard let colon = address.lastIndex(of: ":") else { return nil }
        let digits = address[address.index(after: colon)...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    static func load() async -> Result<[PortUse], ToolError> {
        let output = await Shell.run("/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN -Fpcn", timeout: 12, login: false)
        if output.status != 0, output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(ToolError(detail.isEmpty ? L("没有读到端口占用。") : detail))
        }
        return .success(parse(output.stdout).map { row in
            var copy = row
            copy.canStop = ProcessGuard.canStop(pid: row.pid)
            return copy
        })
    }
}

struct RuntimeProcess: Identifiable, Equatable, Sendable {
    var pid: Int32
    var memoryMB: Int
    var command: String
    var canStop: Bool = true

    var id: Int32 { pid }
}

enum ProcessListing {
    static func parse(_ text: String) -> [RuntimeProcess] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let match = line.wholeMatch(of: /^\s*(\d+)\s+(\d+)\s+([\d.]+)\s+(.+)$/) else { return nil }
            guard let pid = Int32(match.1), pid > 1 else { return nil }
            let command = String(match.4)
            guard isRuntime(command) else { return nil }
            let rss = Int(match.2) ?? 0
            return RuntimeProcess(pid: pid, memoryMB: max(1, rss / 1024), command: command)
        }
        .sorted { $0.memoryMB > $1.memoryMB }
    }

    static func isRuntime(_ command: String) -> Bool {
        let tokens = command.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "." }
        return tokens.contains { token in
            token == "node" || token == "nodejs" || token == "python" || token == "python3" || token.hasPrefix("python3.")
        }
    }

    static func load() async -> Result<[RuntimeProcess], ToolError> {
        let output = await Shell.run("/bin/ps -axo pid=,rss=,pcpu=,command=", timeout: 12, login: false)
        if output.status != 0 {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(ToolError(detail.isEmpty ? L("没有读到进程列表。") : detail))
        }
        return .success(parse(output.stdout).map { row in
            var copy = row
            copy.canStop = ProcessGuard.canStop(pid: row.pid)
            return copy
        })
    }
}

enum ProcessSignal {
    static func send(pid: Int32, force: Bool) async -> String? {
        guard ProcessGuard.canStop(pid: pid) else { return L("不能结束这个进程。") }
        await stopTree(pid: pid, force: force)
        return nil
    }

    /// 只结束这个进程和它拉起来的子进程，不会按进程组去碰别的程序。
    static func stopTree(pid: Int32, force: Bool) async {
        guard ProcessGuard.canStop(pid: pid) else { return }
        let output = await Shell.run("/usr/bin/pgrep -P \(pid)", timeout: 4, login: false)
        let children = output.stdout.split(whereSeparator: \.isNewline).compactMap { line in
            Int32(line.trimmingCharacters(in: .whitespaces))
        }
        for child in children where child != pid {
            await stopTree(pid: child, force: force)
        }
        let signal = force ? "KILL" : "TERM"
        _ = await Shell.run("/bin/kill -\(signal) \(pid)", timeout: 4, login: false)
    }

    /// 退出应用时同步结束，不能再等异步任务。只处理这个进程和它的子进程。
    nonisolated static func stopTreeNow(pid: Int32, depth: Int = 0) {
        guard depth < 16, ProcessGuard.canStop(pid: pid) else { return }
        let children = command("/usr/bin/pgrep", ["-P", "\(pid)"])
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        for child in children where child != pid {
            stopTreeNow(pid: child, depth: depth + 1)
        }
        _ = command("/bin/kill", ["-KILL", "\(pid)"])
    }

    private nonisolated static func command(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
