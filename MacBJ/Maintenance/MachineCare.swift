import Darwin
import Foundation

nonisolated enum ByteText {
    static func string(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(min(bytes, UInt64(Int64.max))))
    }
}

nonisolated struct CommandText: Sendable {
    var status: Int32
    var text: String
}

nonisolated enum MachineCommand {
    private final class Collected: @unchecked Sendable {
        var data = Data()
    }

    /// 读管道的线程必须在进程启动前进入 `read`。否则报错写满管道后，`du` 和 `ps` 会一直停住。
    nonisolated static func run(_ executable: String, _ arguments: [String], includeErrors: Bool = true) -> CommandText {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let out = Collected()
        let err = Collected()
        let group = DispatchGroup()
        group.enter()
        Thread {
            out.data = output.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }.start()
        group.enter()
        Thread {
            err.data = errors.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }.start()
        do {
            try process.run()
        } catch {
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            group.wait()
            return CommandText(status: 1, text: "")
        }
        process.waitUntilExit()
        group.wait()
        var data = out.data
        if includeErrors {
            data += err.data
        }
        return CommandText(status: process.terminationStatus, text: String(decoding: data, as: UTF8.self))
    }
}

nonisolated enum DirectorySize {
    struct Row: Equatable, Sendable {
        var bytes: UInt64
        var path: String
    }

    /// `du -sk` 的一行是「KB 加制表符加路径」。读不到的目录写在错误输出里，这里只认数字行。
    static func parse(_ text: String) -> [Row] {
        text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let raw = String(line)
            guard let tab = raw.firstIndex(of: "\t") else { return nil }
            guard let kilobytes = UInt64(raw[..<tab]) else { return nil }
            let path = String(raw[raw.index(after: tab)...])
            guard !path.isEmpty else { return nil }
            return Row(bytes: kilobytes * 1024, path: path)
        }
    }
}

nonisolated struct MemoryCounts: Equatable, Sendable {
    var pageSize: UInt64
    var free: UInt64
    var speculative: UInt64
    var wired: UInt64
    var compressor: UInt64
    var purgeable: UInt64
    var external: UInt64
    var internalPages: UInt64
    var total: UInt64
}

nonisolated struct MemorySlice: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var bytes: UInt64
}

nonisolated struct MemoryApp: Equatable, Identifiable, Sendable {
    var name: String
    var pid: Int32
    var bytes: UInt64
    var cpu: Double = 0
    var path: String = ""
    var pids: [Int32] = []
    var id: String { "\(pid)-\(name)" }
}

nonisolated struct MemoryReport: Equatable, Sendable {
    var total: UInt64
    var slices: [MemorySlice]
    var apps: [MemoryApp]
    var summary: String
}

nonisolated enum MemoryMap {
    nonisolated static func slices(_ counts: MemoryCounts) -> [MemorySlice] {
        let page = counts.pageSize
        func pages(_ count: UInt64) -> UInt64 { count * page }
        let appPages = counts.internalPages > counts.purgeable ? counts.internalPages - counts.purgeable : 0
        return [
            MemorySlice(id: "app", title: L("应用内存"), bytes: pages(appPages)),
            MemorySlice(id: "wired", title: L("联动内存"), bytes: pages(counts.wired)),
            MemorySlice(id: "compressed", title: L("已压缩"), bytes: pages(counts.compressor)),
            MemorySlice(id: "cached", title: L("缓存文件"), bytes: pages(counts.external + counts.purgeable)),
            MemorySlice(id: "free", title: L("可用"), bytes: pages(counts.free + counts.speculative))
        ]
    }

    nonisolated static func summary(used: UInt64, total: UInt64) -> String {
        guard total > 0 else { return L("读不到物理内存。") }
        let ratio = Double(used) / Double(total)
        if ratio > 0.85 { return L("内存比较紧。可以到「优化速度」里释放，或结束占得多的应用。") }
        if ratio > 0.6 { return L("内存占用中等。") }
        return L("内存还宽裕。")
    }

    /// 命令行里最外层的 `.app` 名称。没有应用包时用可执行文件名。
    nonisolated static func appName(command: String) -> String {
        let icon = iconPath(command: command)
        if icon.hasSuffix(".app") {
            return URL(fileURLWithPath: icon).deletingPathExtension().lastPathComponent
        }
        let name = URL(fileURLWithPath: icon).lastPathComponent
        return name.isEmpty ? command : name
    }

    /// 给图标用的路径。应用包停在最外层 `.app`，其余用可执行文件。
    nonisolated static func iconPath(command: String) -> String {
        if let range = command.range(of: ".app") {
            let end = range.upperBound
            if end == command.endIndex || command[end] == "/" {
                return String(command[..<end])
            }
        }
        let token = command.split(separator: " ").first.map(String.init) ?? command
        return token
    }

    nonisolated static func group(_ rows: [(pid: Int32, bytes: UInt64, cpu: Double, command: String)], limit: Int = 12) -> [MemoryApp] {
        var grouped: [String: MemoryApp] = [:]
        for row in rows where row.pid > 0 && row.bytes > 0 {
            let name = appName(command: row.command)
            let icon = iconPath(command: row.command)
            if var existing = grouped[name] {
                existing.bytes += row.bytes
                existing.cpu += row.cpu
                existing.pid = min(existing.pid, row.pid)
                existing.pids.append(row.pid)
                if icon.hasSuffix(".app"), !existing.path.hasSuffix(".app") {
                    existing.path = icon
                }
                grouped[name] = existing
            } else {
                grouped[name] = MemoryApp(name: name, pid: row.pid, bytes: row.bytes, cpu: row.cpu, path: icon, pids: [row.pid])
            }
        }
        return grouped.values.sorted { lhs, rhs in
            if lhs.bytes == rhs.bytes { return lhs.pid < rhs.pid }
            return lhs.bytes > rhs.bytes
        }.prefix(limit).map { $0 }
    }

    nonisolated static func snapshot() -> MemoryReport {
        let counts = readCounts()
        let slices = slices(counts)
        let used = slices.filter { $0.id != "free" && $0.id != "cached" }.reduce(UInt64(0)) { $0 + $1.bytes }
        return MemoryReport(
            total: counts.total,
            slices: slices,
            apps: group(processes()),
            summary: summary(used: used, total: counts.total)
        )
    }

    nonisolated private static func readCounts() -> MemoryCounts {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        var page: vm_size_t = 0
        if result == KERN_SUCCESS {
            host_page_size(mach_host_self(), &page)
        }
        var total: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &totalSize, nil, 0)
        guard result == KERN_SUCCESS, page > 0 else {
            return MemoryCounts(pageSize: 0, free: 0, speculative: 0, wired: 0, compressor: 0, purgeable: 0, external: 0, internalPages: 0, total: total)
        }
        return MemoryCounts(
            pageSize: UInt64(page),
            free: UInt64(stats.free_count),
            speculative: UInt64(stats.speculative_count),
            wired: UInt64(stats.wire_count),
            compressor: UInt64(stats.compressor_page_count),
            purgeable: UInt64(stats.purgeable_count),
            external: UInt64(stats.external_page_count),
            internalPages: UInt64(stats.internal_page_count),
            total: total
        )
    }

    nonisolated private static func processes() -> [(pid: Int32, bytes: UInt64, cpu: Double, command: String)] {
        let cpus = cpuByPID()
        var capacity = 2048
        var pids = [pid_t](repeating: 0, count: capacity)
        var written = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        if written >= Int32(capacity * MemoryLayout<pid_t>.size) {
            capacity = 8192
            pids = [pid_t](repeating: 0, count: capacity)
            written = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        }
        let count = max(0, Int(written) / MemoryLayout<pid_t>.size)
        var rows: [(pid: Int32, bytes: UInt64, cpu: Double, command: String)] = []
        rows.reserveCapacity(count)
        for pid in pids.prefix(count) where pid > 0 {
            guard let bytes = footprint(pid) ?? resident(pid), bytes > 0 else { continue }
            rows.append((pid, bytes, cpus[pid] ?? 0, path(pid)))
        }
        return rows
    }

    nonisolated private static func cpuByPID() -> [Int32: Double] {
        var map: [Int32: Double] = [:]
        for line in MachineCommand.run("/bin/ps", ["-axo", "pid=,pcpu="]).text.split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2, let pid = Int32(fields[0]), let cpu = Double(fields[1]) else { continue }
            map[pid] = cpu
        }
        return map
    }

    nonisolated private static func footprint(_ pid: pid_t) -> UInt64? {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V2, rebound)
            }
        }
        guard result == 0 else { return nil }
        return info.ri_phys_footprint
    }

    nonisolated private static func resident(_ pid: pid_t) -> UInt64? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        let got = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size)
        guard got == size else { return nil }
        return info.pti_resident_size
    }

    nonisolated private static func path(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return L("进程 %@", String(pid)) }
        return String(cString: buffer)
    }
}

nonisolated enum SpotlightDate {
    static func parse(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "-", trimmed != "(null)" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.date(from: trimmed)
    }
}

nonisolated enum LastUsedText {
    static func string(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

nonisolated struct InstalledApp: Equatable, Identifiable, Sendable {
    var name: String
    var bundleID: String
    var path: String
    var version: String
    var bytes: UInt64?
    var leftovers: [String]
    var lastUsed: Date?
    var removable: Bool
    var reason: String?
    var id: String { path }
}

nonisolated enum AppUninstall {
    static let ownBundleID = "app.macbj.desktop"

    struct Identity: Equatable, Sendable {
        var name: String
        var bundleID: String
    }

    nonisolated static func safeToken(_ value: String) -> Bool {
        !value.isEmpty
            && !value.contains("/")
            && !value.contains("\0")
            && !value.hasPrefix(".")
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
    }

    /// 显示名可以有空格，但不能换成别的路径。
    nonisolated static func safeName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "." && trimmed != ".." && !trimmed.contains("/") && !trimmed.contains("\0") && !trimmed.hasPrefix(".")
    }

    /// 只按包标识精确对应。应用名只补「应用支持」和「日志」，而且必须完全同名。
    nonisolated static func candidates(library: URL, identity: Identity) -> [URL] {
        guard safeToken(identity.bundleID) else { return [] }
        let id = identity.bundleID
        var paths: [URL] = [
            library.appendingPathComponent("Preferences/\(id).plist"),
            library.appendingPathComponent("Caches/\(id)"),
            library.appendingPathComponent("Application Support/\(id)"),
            library.appendingPathComponent("Logs/\(id)"),
            library.appendingPathComponent("Saved Application State/\(id).savedState"),
            library.appendingPathComponent("HTTPStorages/\(id)"),
            library.appendingPathComponent("WebKit/\(id)"),
            library.appendingPathComponent("Containers/\(id)"),
            library.appendingPathComponent("Cookies/\(id).binarycookies"),
            library.appendingPathComponent("Application Scripts/\(id)")
        ]
        if safeName(identity.name), identity.name != id {
            paths.append(library.appendingPathComponent("Application Support/\(identity.name)"))
            paths.append(library.appendingPathComponent("Logs/\(identity.name)"))
        }
        return paths
    }

    /// 别的已装应用也会认的路径留下来。
    nonisolated static func deletionSet(library: URL, app: Identity, others: [Identity]) -> [URL] {
        let mine = Set(candidates(library: library, identity: app).map(\.path))
        let shared = Set(others.flatMap { candidates(library: library, identity: $0).map(\.path) })
        return mine.subtracting(shared).sorted().map { URL(fileURLWithPath: $0) }
    }

    nonisolated static func isDirectApp(path: String, home: URL) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension == "app" else { return false }
        let parents = [
            URL(fileURLWithPath: "/Applications").standardizedFileURL.path,
            home.appendingPathComponent("Applications").standardizedFileURL.path
        ]
        return parents.contains(url.deletingLastPathComponent().path)
    }

    nonisolated static func inventory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [InstalledApp] {
        let library = home.appendingPathComponent("Library")
        let folders = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var found: [InstalledApp] = []
        var identities: [Identity] = []
        let manager = FileManager.default
        for folder in folders {
            let children = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in children where url.pathExtension == "app" {
                guard let identity = readIdentity(url) else { continue }
                identities.append(identity)
                let real = url.resolvingSymlinksInPath().path
                let own = identity.bundleID == ownBundleID
                let system = real.hasPrefix("/System/")
                let removable = !own && !system
                let reason = own ? L("不能从这里卸载泊位") : (system ? L("这是系统自带的应用") : nil)
                found.append(InstalledApp(
                    name: identity.name,
                    bundleID: identity.bundleID,
                    path: url.standardizedFileURL.path,
                    version: version(of: url),
                    bytes: nil,
                    leftovers: [],
                    lastUsed: nil,
                    removable: removable,
                    reason: reason
                ))
            }
        }
        for index in found.indices {
            let identity = Identity(name: found[index].name, bundleID: found[index].bundleID)
            let others = identities.enumerated().filter { $0.offset != index }.map(\.element)
            let existing = deletionSet(library: library, app: identity, others: others).filter { manager.fileExists(atPath: $0.path) }
            found[index].leftovers = existing.map(\.path)
        }
        return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated static func lastUsed(paths: [String]) -> [String: Date] {
        var found: [String: Date] = [:]
        var index = 0
        while index < paths.count {
            let slice = Array(paths[index..<min(index + 40, paths.count)])
            index += slice.count
            var arguments = ["-name", "kMDItemLastUsedDate", "-raw", "-nullMarker", "-"]
            arguments.append(contentsOf: slice)
            let result = MachineCommand.run("/usr/bin/mdls", arguments)
            guard result.status == 0 else { continue }
            let fields = result.text.split(separator: "\0", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            for (path, field) in zip(slice, fields) {
                if let date = SpotlightDate.parse(field) {
                    found[path] = date
                }
            }
        }
        return found
    }

    nonisolated static func allocatedSize(_ path: String, control: AllocatedSize.ScanControl? = nil) -> UInt64 {
        AllocatedSize.tree(path, deadline: Date().addingTimeInterval(20), control: control).bytes
    }

    nonisolated static func trash(_ app: InstalledApp, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let url = URL(fileURLWithPath: app.path)
        guard isDirectApp(path: app.path, home: home) else { throw ToolError(L("路径不在允许卸载的范围内")) }
        guard let identity = readIdentity(url), identity.bundleID == app.bundleID else {
            throw ToolError(L("应用已经变化，先刷新再卸载"))
        }
        guard identity.bundleID != ownBundleID else { throw ToolError(L("不能从这里卸载泊位")) }
        guard !url.resolvingSymlinksInPath().path.hasPrefix("/System/") else { throw ToolError(L("这是系统自带的应用")) }
        let library = home.appendingPathComponent("Library")
        let others = inventory(home: home).filter { $0.path != app.path }.map { Identity(name: $0.name, bundleID: $0.bundleID) }
        let leftovers = deletionSet(library: library, app: identity, others: others).filter {
            FileManager.default.fileExists(atPath: $0.path) && isInsideLibrary($0, library: library)
        }
        var failed: [String] = []
        for leftover in leftovers {
            do {
                try FileManager.default.trashItem(at: leftover, resultingItemURL: nil)
            } catch {
                failed.append(leftover.lastPathComponent)
            }
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            throw ToolError(failed.isEmpty ? L("应用没有移到废纸篓。") : L("应用没有移到废纸篓。残留也有没移走的。"))
        }
        if !failed.isEmpty {
            throw ToolError(L("应用已移到废纸篓。这些残留没能移走：%@", failed.prefix(4).joined(separator: L("、"))))
        }
    }

    nonisolated private static func isInsideLibrary(_ url: URL, library: URL) -> Bool {
        let root = library.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root + "/")
    }

    nonisolated private static func readIdentity(_ url: URL) -> Identity? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String,
              safeToken(bundleID)
        else { return nil }
        let display = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String)
        let name = (display?.isEmpty == false ? display! : url.deletingPathExtension().lastPathComponent)
        guard safeName(name) else { return nil }
        return Identity(name: name, bundleID: bundleID)
    }

    nonisolated private static func version(of url: URL) -> String {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return "" }
        return plist["CFBundleShortVersionString"] as? String ?? ""
    }
}

nonisolated struct CacheTarget: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var detail: String
    var bytes: UInt64
    var pending: Bool
    var partial: Bool = false
    var selected: Bool
}

nonisolated enum CacheClean {
    struct Spec: Sendable {
        var id: String
        var title: String
        var detail: String
        var relative: String
        var also: [String] = []
        var selected: Bool
    }

    nonisolated static let specs: [Spec] = [
        Spec(id: "user-caches", title: L("用户缓存"), detail: L("应用重新打开后会再生成。"), relative: "Library/Caches", selected: true),
        Spec(id: "user-logs", title: L("用户日志"), detail: L("诊断日志，删了不影响文件。"), relative: "Library/Logs", selected: true),
        Spec(id: "trash", title: L("废纸篓"), detail: L("清空当前用户的废纸篓。"), relative: ".Trash", selected: true),
        Spec(id: "xcode-derived", title: L("Xcode 派生数据"), detail: L("下次编译会重新生成，第一次会慢一些。"), relative: "Library/Developer/Xcode/DerivedData", selected: false),
        Spec(id: "xcode-devices", title: L("Xcode 设备支持文件"), detail: L("插上设备后会重新生成。"), relative: "Library/Developer/Xcode/iOS DeviceSupport", also: [
            "Library/Developer/Xcode/watchOS DeviceSupport",
            "Library/Developer/Xcode/tvOS DeviceSupport",
            "Library/Developer/Xcode/visionOS DeviceSupport"
        ], selected: false),
        Spec(id: "simulator", title: L("模拟器缓存"), detail: L("模拟器下次启动会再生成。"), relative: "Library/Developer/CoreSimulator/Caches", selected: false),
        Spec(id: "homebrew", title: L("Homebrew 缓存"), detail: L("已下载的安装包。下次安装会重新下载。"), relative: "Library/Caches/Homebrew", selected: false),
        Spec(id: "npm", title: L("npm 缓存"), detail: L("只清缓存目录，不删已安装的包。"), relative: ".npm/_cacache", selected: false),
        Spec(id: "pnpm", title: L("pnpm 仓库"), detail: L("已下载的包。下次安装会重新下载。"), relative: "Library/pnpm/store", selected: false),
        Spec(id: "yarn", title: L("Yarn 缓存"), detail: L("已下载的包。不删项目里的 node_modules。"), relative: ".cache/yarn", selected: false),
        Spec(id: "pip", title: L("pip 缓存"), detail: L("已下载的 Python 包。"), relative: "Library/Caches/pip", selected: false),
        Spec(id: "uv", title: L("uv 缓存"), detail: L("已下载的 Python 包。"), relative: ".cache/uv", selected: false),
        Spec(id: "go", title: L("Go 构建缓存"), detail: L("编译缓存。下次构建会重新生成。"), relative: "Library/Caches/go-build", selected: false),
        Spec(id: "go-mod", title: L("Go 模块缓存"), detail: L("已下载的模块。下次构建会重新下载。"), relative: "go/pkg/mod", selected: false),
        Spec(id: "cargo", title: L("Rust 下载缓存"), detail: L("crates 的压缩包。已检出的源码不动。"), relative: ".cargo/registry/cache", selected: false),
        Spec(id: "gradle", title: L("Gradle 缓存"), detail: L("已下载的依赖。下次构建会重新下载。"), relative: ".gradle/caches", selected: false),
        Spec(id: "maven", title: L("Maven 仓库"), detail: L("已下载的依赖。项目源码不动。"), relative: ".m2/repository", selected: false),
        Spec(id: "cocoapods", title: L("CocoaPods 仓库"), detail: L("spec 仓库。下次 pod install 会再拉。"), relative: ".cocoapods/repos", selected: false),
        Spec(id: "pub", title: L("Pub 缓存"), detail: L("已下载的 Dart 包。"), relative: ".pub-cache/hosted", selected: false),
        Spec(id: "cursor", title: L("Cursor 缓存"), detail: L("界面缓存和日志。对话和设置不在这里。"), relative: "Library/Application Support/Cursor/Cache", also: [
            "Library/Application Support/Cursor/CachedData",
            "Library/Application Support/Cursor/Code Cache",
            "Library/Application Support/Cursor/logs"
        ], selected: false),
        Spec(id: "claude", title: L("Claude 缓存"), detail: L("界面缓存。对话记录不在这里。"), relative: "Library/Application Support/Claude/Cache", also: [
            "Library/Application Support/Claude/Code Cache",
            ".claude/paste-cache",
            ".claude/shell-snapshots"
        ], selected: false)
    ]

    nonisolated static func accepts(child: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let childPath = child.standardizedFileURL.resolvingSymlinksInPath().path
        guard rootPath != "/" , rootPath != FileManager.default.homeDirectoryForCurrentUser.path else { return false }
        return childPath == rootPath || childPath.hasPrefix(rootPath + "/")
    }

    nonisolated static func locations(for spec: Spec, home: URL) -> [URL] {
        ([spec.relative] + spec.also).compactMap { relative in
            let url = home.appendingPathComponent(relative)
            var directory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { return nil }
            return url
        }
    }

    nonisolated static func existing(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CacheTarget] {
        specs.compactMap { spec in
            guard !locations(for: spec, home: home).isEmpty else { return nil }
            return CacheTarget(id: spec.id, title: spec.title, detail: spec.detail, bytes: 0, pending: true, selected: spec.selected)
        }
    }

    nonisolated static func measure(id: String, home: URL = FileManager.default.homeDirectoryForCurrentUser, control: AllocatedSize.ScanControl? = nil) -> (bytes: UInt64, complete: Bool) {
        guard let spec = specs.first(where: { $0.id == id }) else { return (0, true) }
        var total: UInt64 = 0
        var complete = true
        let deadline = Date().addingTimeInterval(20)
        for url in locations(for: spec, home: home) {
            if control?.isStopped == true { complete = false; break }
            let part = AllocatedSize.breakdown(url.path, deadline: deadline, control: control)
            total += part.bytes
            complete = complete && part.complete
        }
        return (total, complete)
    }

    nonisolated static func survey(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CacheTarget] {
        existing(home: home).compactMap { target in
            let measured = measure(id: target.id, home: home)
            guard measured.bytes > 0 else { return nil }
            var copy = target
            copy.bytes = measured.bytes
            copy.partial = !measured.complete
            copy.pending = false
            return copy
        }
    }

    nonisolated static func clean(ids: Set<String>, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> UInt64 {
        var freed: UInt64 = 0
        for spec in specs where ids.contains(spec.id) {
            for root in locations(for: spec, home: home) {
                freed += try removeChildren(of: root, home: home)
            }
        }
        return freed
    }

    nonisolated static func usage(of root: URL) -> UInt64 {
        let manager = FileManager.default
        guard let children = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: []) else { return 0 }
        return children.reduce(UInt64(0)) { partial, child in
            guard accepts(child: child, root: root) else { return partial }
            return partial + allocated(child)
        }
    }

    nonisolated private static func removeChildren(of root: URL, home: URL) throws -> UInt64 {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        let allowed = specs.contains { spec in
            locations(for: spec, home: home).contains { $0.standardizedFileURL.resolvingSymlinksInPath().path == rootPath }
        }
        guard allowed else { throw ToolError(L("这个位置不在可清理的范围内")) }
        let manager = FileManager.default
        let children = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? []
        var freed: UInt64 = 0
        var failed = 0
        for child in children {
            guard accepts(child: child, root: root) else { continue }
            let size = allocated(child)
            do {
                try manager.removeItem(at: child)
                freed += size
            } catch {
                failed += 1
            }
        }
        if failed > 0, freed == 0 { throw ToolError(L("这些文件正在使用，没有清理掉")) }
        return freed
    }

    nonisolated private static func allocated(_ url: URL) -> UInt64 {
        AllocatedSize.breakdown(url.path, deadline: Date().addingTimeInterval(20)).bytes
    }
}

nonisolated struct SpeedHog: Equatable, Identifiable, Sendable {
    var pid: Int32
    var name: String
    var cpu: Double
    var bytes: UInt64
    var canStop: Bool = true
    var id: Int32 { pid }
}

nonisolated struct SpeedLoginItem: Equatable, Identifiable, Sendable {
    var name: String
    var enabled: Bool
    var path: String
    var label: String
    var id: String { path }
}

nonisolated enum SpeedTune {
    nonisolated static func parseDisabled(_ text: String) -> [String: Bool] {
        var result: [String: Bool] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=>", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let enabled: Bool? = switch parts[1] {
            case "enabled", "false": true
            case "disabled", "true": false
            default: nil
            }
            if let enabled { result[label] = enabled }
        }
        return result
    }

    nonisolated static func safeLabel(_ label: String) -> Bool {
        AppUninstall.safeToken(label)
    }

    nonisolated static func hogs(limit: Int = 10) -> [SpeedHog] {
        let text = MachineCommand.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm="]).text
        var rows: [SpeedHog] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard fields.count >= 4, let pid = Int32(fields[0]), let cpu = Double(fields[1]), let rss = UInt64(fields[2]) else { continue }
            let name = fields.dropFirst(3).joined(separator: " ")
            guard cpu >= 1 || rss > 200_000 else { continue }
            let executable = ProcessGuard.executablePath(pid: pid)
            rows.append(SpeedHog(
                pid: pid,
                name: name,
                cpu: cpu,
                bytes: rss * 1024,
                canStop: ProcessGuard.canStop(pid: pid, path: executable)
            ))
        }
        return rows.sorted { lhs, rhs in
            if lhs.cpu == rhs.cpu { return lhs.bytes > rhs.bytes }
            return lhs.cpu > rhs.cpu
        }.prefix(limit).map { $0 }
    }

    nonisolated static func loginItems(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SpeedLoginItem] {
        let directory = home.appendingPathComponent("Library/LaunchAgents")
        let overrides = parseDisabled(MachineCommand.run("/bin/launchctl", ["print-disabled", "gui/\(getuid())"]).text)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var items: [SpeedLoginItem] = []
        for file in files where file.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let fallback = file.deletingPathExtension().lastPathComponent
            let label = (plist["Label"] as? String).flatMap { safeLabel($0) ? $0 : nil } ?? fallback
            guard safeLabel(label) else { continue }
            let disabled = (plist["Disabled"] as? Bool) == true
            let enabled = overrides[label] ?? !disabled
            items.append(SpeedLoginItem(name: label, enabled: enabled, path: file.path, label: label))
        }
        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    nonisolated static func quit(pid: Int32, name _: String) throws {
        guard ProcessGuard.canStop(pid: pid) else { throw ToolError(L("不能结束这个进程。")) }
        guard kill(pid, SIGTERM) == 0 else { throw ToolError(L("没有结束这个进程")) }
    }

    nonisolated static func setAgent(label: String, enabled: Bool, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        guard safeLabel(label) else { throw ToolError(L("这个启动项不能从这里改")) }
        let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        guard FileManager.default.fileExists(atPath: plist.path) else { throw ToolError(L("只改用户目录里的启动代理")) }
        let action = enabled ? "enable" : "disable"
        let result = MachineCommand.run("/bin/launchctl", [action, "gui/\(getuid())/\(label)"])
        guard result.status == 0 else {
            let detail = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolError(detail.isEmpty ? L("没有改成这个状态") : detail)
        }
    }

    nonisolated static func administrator(_ shell: String) async -> String? {
        let outcome = await Task.detached(priority: .userInitiated) {
            PrivilegedShell.run(shell)
        }.value
        if outcome.cancelled {
            return L("没有继续。取消密码框后不会改任何东西。")
        }
        if outcome.status == 0 { return nil }
        let detail = outcome.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty || detail.contains("User canceled") || detail.contains("-128") {
            return L("没有继续。取消密码框后不会改任何东西。")
        }
        return detail
    }
}
