import Darwin
import Foundation

/// 不能结束的进程：泊位自己、pid 1，以及系统目录里的可执行文件。
/// `/usr/local` 不算系统目录。
nonisolated enum ProcessGuard {
    nonisolated static func executablePath(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return proc_pidpath(pid, base, UInt32(raw.count))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// 整段命令以 `/` 开头时保留空格。用户目录路径里常有空格，不能只取第一段。
    nonisolated static func absoluteExecutable(in command: String?) -> String? {
        guard let command else { return nil }
        let token = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("/") else { return nil }
        return token
    }

    /// 可执行文件或应用包落在系统目录里。
    nonisolated static func isSystemLocation(_ path: String) -> Bool {
        if path == "/usr/local" || path.hasPrefix("/usr/local/") { return false }
        let roots = ["/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/"]
        return roots.contains { path.hasPrefix($0) }
    }

    nonisolated static func isThisApp(pid: Int32, path: String?) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier { return true }
        guard let path else { return false }
        if let own = Bundle.main.executableURL?.resolvingSymlinksInPath().path, path == own {
            return true
        }
        return path.contains("/泊位.app/") || path.contains("/MacBJ.app/")
    }

    /// 读不到路径时允许结束。只有已经确认落在系统目录或泊位自己才拒绝。
    nonisolated static func canStop(resolvedPath path: String?) -> Bool {
        guard let path else { return true }
        if isSystemLocation(path) { return false }
        if path.contains("/泊位.app/") || path.contains("/MacBJ.app/") { return false }
        return true
    }

    /// 只有已经确认是泊位或系统目录里的可执行文件才拒绝结束。
    /// 读不到路径时不拦截：用户目录里的进程常常只能从 lsof 的命令里看到路径。
    nonisolated static func canStop(pid: Int32, path: String? = nil, command: String? = nil) -> Bool {
        if pid <= 1 { return false }
        let resolved = path ?? executablePath(pid: pid) ?? absoluteExecutable(in: command)
        if isThisApp(pid: pid, path: resolved) { return false }
        return canStop(resolvedPath: resolved)
    }
}
