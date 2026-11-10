import Darwin
import Foundation

/// 不能结束的进程：泊位自己、pid 1，以及系统目录里的可执行文件。
/// `/usr/local` 不算系统目录。
nonisolated enum ProcessGuard {
    nonisolated static func executablePath(pid: Int32) -> String? {
        guard pid > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
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

    /// `path` 为 nil 时会再读一次进程路径。读不到路径时拒绝结束，避免误伤没有路径的系统进程。
    nonisolated static func canStop(pid: Int32, path: String? = nil) -> Bool {
        if pid <= 1 { return false }
        let resolved = path ?? executablePath(pid: pid)
        if isThisApp(pid: pid, path: resolved) { return false }
        guard let resolved else { return false }
        if isSystemLocation(resolved) { return false }
        return true
    }
}
