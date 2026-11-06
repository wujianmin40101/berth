import Darwin
import Foundation

/// 多线程按目录汇总实际占用，并留下每一层里最大的那些子目录，方便点进去看。
/// 不跟随符号链接。`/System/Volumes/Data` 和用户目录是同一棵树，不能再算进 System。
nonisolated enum AllocatedSize {
    struct Child: Sendable {
        var path: String
        var bytes: UInt64
        var complete: Bool
    }

    struct Breakdown: Sendable {
        var bytes: UInt64
        var complete: Bool
        var children: [Child]
    }

    struct Entry: Sendable {
        var name: String
        var path: String
        var bytes: UInt64
        var complete: Bool
        var children: [Entry]
    }

    /// 每个目录只保留占用最大的这一批，其余并进「其他」，父目录的总字节仍然是全部。
    static let keptChildren = 40

    /// 页面离开时调用 `stop()`，正在进行的统计会停下来并交回已经数到的大小。
    nonisolated final class ScanControl: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
        }

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }
    }

    static func tree(_ path: String, deadline: Date, control: ScanControl? = nil) -> Entry {
        var info = Darwin.stat()
        guard lstat(path, &info) == 0 else {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return Entry(name: name, path: path, bytes: 0, complete: true, children: [])
        }
        let own = UInt64(info.st_blocks) * 512
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard info.st_mode & S_IFMT == S_IFDIR else {
            return Entry(name: name, path: path, bytes: own, complete: true, children: [])
        }
        let root = Dir(name: name.isEmpty ? path : name, path: path, fileBytes: own, depth: 0)
        root.inode = UInt64(info.st_ino)
        let walk = Walk(device: UInt32(bitPattern: info.st_dev), deadline: deadline, root: root, control: control)
        walk.run()
        return walk.entry()
    }

    static func breakdown(_ path: String, deadline: Date, control: ScanControl? = nil) -> Breakdown {
        let root = tree(path, deadline: deadline, control: control)
        let children = root.children.filter { $0.name != L("其他") }.map {
            Child(path: $0.path, bytes: $0.bytes, complete: $0.complete)
        }
        return Breakdown(bytes: root.bytes, complete: root.complete, children: children)
    }
}

private nonisolated final class Dir {
    let name: String
    let path: String
    var fileBytes: UInt64
    var folded: UInt64 = 0
    var kids: [Dir] = []
    var waiting = 0
    var complete = true
    var sealed = false
    var bytes: UInt64 = 0
    var depth: Int
    var inode: UInt64 = 0
    weak var parent: Dir?

    init(name: String, path: String, fileBytes: UInt64, depth: Int) {
        self.name = name
        self.path = path
        self.fileBytes = fileBytes
        self.depth = depth
    }
}

private struct Listed {
    var files: UInt64
    var dirs: [(name: String, path: String, bytes: UInt64, inode: UInt64)]
    var readable: Bool
}

private nonisolated func excluded(parent: String, name: String) -> Bool {
    parent == "/System/Volumes" && name == "Data"
}

private nonisolated func list(_ path: String, device: UInt32, walk: Walk) -> Listed {
    guard walk.acquirePermit() else { return Listed(files: 0, dirs: [], readable: false) }
    defer { walk.releasePermit() }
    if walk.shouldStop() { return Listed(files: 0, dirs: [], readable: false) }
    let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    if fd < 0 { return Listed(files: 0, dirs: [], readable: false) }
    var handed = false
    guard walk.track(fd) else { return Listed(files: 0, dirs: [], readable: false) }
    defer {
        if walk.untrack(fd), !handed { close(fd) }
    }
    if walk.shouldStop() { return Listed(files: 0, dirs: [], readable: false) }
    let bulk = listBulk(fd: fd, path: path, device: device, walk: walk)
    if bulk.supported {
        return Listed(files: bulk.files, dirs: bulk.dirs, readable: bulk.readable)
    }
    handed = true
    return listFd(fd, path: path, device: device, walk: walk)
}

private nonisolated func listBulk(fd: Int32, path: String, device: UInt32, walk: Walk) -> (files: UInt64, dirs: [(name: String, path: String, bytes: UInt64, inode: UInt64)], readable: Bool, supported: Bool) {
    var attr = attrlist()
    memset(&attr, 0, MemoryLayout<attrlist>.size)
    attr.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    attr.commonattr = 0x8000_0001 | 0x0000_0002 | 0x0000_0008 | 0x0200_0000 | 0x2000_0000
    attr.fileattr = 0x0000_0004
    attr.dirattr = 0x0000_0008
    let capacity = 256 * 1024
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
    defer { buffer.deallocate() }
    var files: UInt64 = 0
    var dirs: [(name: String, path: String, bytes: UInt64, inode: UInt64)] = []
    while !walk.shouldStop() {
        let count = getattrlistbulk(fd, &attr, buffer, capacity, 0)
        if count == 0 { break }
        if count < 0 {
            let error = errno
            if files == 0, dirs.isEmpty, error == ENOTSUP || error == EINVAL || error == ENOTTY {
                return (0, [], true, false)
            }
            return (files, dirs, false, true)
        }
        let raw = UnsafeRawBufferPointer(start: buffer, count: capacity)
        var cursor = 0
        for _ in 0..<Int(count) {
            guard cursor + 4 <= capacity else { return (files, dirs, false, true) }
            let length = Int(raw.loadUnaligned(fromByteOffset: cursor, as: UInt32.self))
            guard length >= 24, cursor + length <= capacity else { return (files, dirs, false, true) }
            let recordEnd = cursor + length
            var field = cursor + 4
            let common = raw.loadUnaligned(fromByteOffset: field, as: UInt32.self)
            let dirattr = raw.loadUnaligned(fromByteOffset: field + 8, as: UInt32.self)
            let fileattr = raw.loadUnaligned(fromByteOffset: field + 12, as: UInt32.self)
            field += 20
            var name = ""
            if common & 0x1 != 0, field + 8 <= recordEnd {
                let relative = Int(raw.loadUnaligned(fromByteOffset: field, as: Int32.self))
                let nameLen = Int(raw.loadUnaligned(fromByteOffset: field + 4, as: UInt32.self))
                let start = field + relative
                if nameLen > 1, start >= cursor, start < recordEnd {
                    var bytes: [UInt8] = []
                    let end = min(recordEnd, start + nameLen)
                    bytes.reserveCapacity(max(0, end - start))
                    var index = start
                    while index < end {
                        let byte = raw[index]
                        if byte == 0 { break }
                        bytes.append(byte)
                        index += 1
                    }
                    name = String(bytes: bytes, encoding: .utf8) ?? ""
                }
                field += 8
            }
            var sameDevice = true
            if common & 0x2 != 0, field + 4 <= recordEnd {
                let dev = raw.loadUnaligned(fromByteOffset: field, as: UInt32.self)
                sameDevice = dev == device
                field += 4
            }
            var kind: UInt32 = 0
            if common & 0x8 != 0, field + 4 <= recordEnd {
                kind = raw.loadUnaligned(fromByteOffset: field, as: UInt32.self)
                field += 4
            }
            var inode: UInt64 = 0
            if common & 0x0200_0000 != 0 {
                let aligned = (field + 7) & ~7
                if aligned + 8 <= recordEnd {
                    inode = raw.loadUnaligned(fromByteOffset: aligned, as: UInt64.self)
                    field = aligned + 8
                }
            }
            var failed = false
            if common & 0x2000_0000 != 0, field + 4 <= recordEnd {
                failed = raw.loadUnaligned(fromByteOffset: field, as: UInt32.self) != 0
                field += 4
            }
            var alloc: UInt64 = 0
            if !failed, dirattr & 0x8 != 0 || fileattr & 0x4 != 0 {
                let aligned = (field + 7) & ~7
                if aligned + 8 <= recordEnd {
                    alloc = raw.loadUnaligned(fromByteOffset: aligned, as: UInt64.self)
                }
            }
            if !failed, !name.isEmpty, name != ".", name != "..", sameDevice {
                let isDir = kind == 2 || (kind == 0 && dirattr & 0x8 != 0 && fileattr & 0x4 == 0)
                if isDir, !excluded(parent: path, name: name) {
                    let child = path == "/" ? "/" + name : path + "/" + name
                    dirs.append((name, child, alloc, inode))
                } else if !isDir {
                    files += alloc
                }
            }
            cursor = recordEnd
        }
    }
    return (files, dirs, !walk.shouldStop(), true)
}

private nonisolated func listFd(_ fd: Int32, path: String, device: UInt32, walk: Walk) -> Listed {
    guard let dir = fdopendir(fd) else {
        close(fd)
        return Listed(files: 0, dirs: [], readable: false)
    }
    defer { closedir(dir) }
    var files: UInt64 = 0
    var dirs: [(name: String, path: String, bytes: UInt64, inode: UInt64)] = []
    while !walk.shouldStop(), let entry = readdir(dir) {
        let name = direntName(entry)
        if name == "." || name == ".." || excluded(parent: path, name: name) { continue }
        var info = Darwin.stat()
        if fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) != 0 || UInt32(bitPattern: info.st_dev) != device { continue }
        let bytes = UInt64(info.st_blocks) * 512
        if info.st_mode & S_IFMT == S_IFDIR {
            let child = path == "/" ? "/" + name : path + "/" + name
            dirs.append((name, child, bytes, UInt64(info.st_ino)))
        } else {
            files += bytes
        }
    }
    return Listed(files: files, dirs: dirs, readable: !walk.shouldStop())
}

private nonisolated func direntName(_ entry: UnsafeMutablePointer<dirent>) -> String {
    var name = entry.pointee.d_name
    return withUnsafePointer(to: &name) {
        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
            String(cString: $0)
        }
    }
}

nonisolated(unsafe) private let listPermits = DispatchSemaphore(value: 4)

private nonisolated final class Walk: @unchecked Sendable {
    private let lock = NSLock()
    private let device: UInt32
    private let deadline: Date
    private let control: AllocatedSize.ScanControl?
    private let root: Dir
    private var queue: [Dir]
    private var busy = 0
    private var finished: Dir?
    private var seen = Set<UInt64>()
    private var descriptors = Set<Int32>()
    private var stopping = false
    private var abandoned = false
    /// 父指针是 weak。目录在算完之前不能只靠队列托着，否则子目录还没回来，父目录就被释放了。
    private var retained: [Dir]

    init(device: UInt32, deadline: Date, root: Dir, control: AllocatedSize.ScanControl?) {
        self.device = device
        self.deadline = deadline
        self.control = control
        self.root = root
        self.queue = [root]
        self.retained = [root]
    }

    func run() {
        let count = max(2, min(3, ProcessInfo.processInfo.activeProcessorCount))
        let threads = (0..<count).map { _ in
            Thread { [self] in
                self.worker()
            }
        }
        threads.forEach { $0.start() }
        var stopNoted: Date?
        while threads.contains(where: { !$0.isFinished }) {
            if shouldStop() {
                if stopNoted == nil { stopNoted = Date() }
                requestStop()
                if let stopNoted, Date().timeIntervalSince(stopNoted) > 1 {
                    lock.lock()
                    abandoned = true
                    if finished == nil {
                        root.complete = false
                        finish(root)
                    }
                    lock.unlock()
                    return
                }
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        lock.lock()
        if finished == nil {
            root.complete = false
            finish(root)
        }
        lock.unlock()
    }

    func entry() -> AllocatedSize.Entry {
        lock.lock()
        let node = finished ?? root
        let result = convert(node)
        let drop = !abandoned
        lock.unlock()
        if drop { retained.removeAll(keepingCapacity: false) }
        return result
    }

    func shouldStop() -> Bool {
        if Date() >= deadline || control?.isStopped == true { return true }
        lock.lock()
        let flag = stopping || abandoned
        lock.unlock()
        return flag
    }

    func acquirePermit() -> Bool {
        while true {
            if shouldStop() { return false }
            if listPermits.wait(timeout: .now() + .milliseconds(200)) == .success {
                if shouldStop() {
                    listPermits.signal()
                    return false
                }
                return true
            }
        }
    }

    func releasePermit() {
        listPermits.signal()
    }

    func track(_ fd: Int32) -> Bool {
        lock.lock()
        if stopping || abandoned {
            lock.unlock()
            close(fd)
            return false
        }
        descriptors.insert(fd)
        lock.unlock()
        return true
    }

    func untrack(_ fd: Int32) -> Bool {
        lock.lock()
        let owned = descriptors.remove(fd) != nil
        lock.unlock()
        return owned
    }

    private func requestStop() {
        lock.lock()
        stopping = true
        expireLocked()
        let open = descriptors
        descriptors.removeAll()
        lock.unlock()
        for fd in open { close(fd) }
    }

    private func worker() {
        while true {
            lock.lock()
            if abandoned {
                lock.unlock()
                return
            }
            if stopping || Date() >= deadline || control?.isStopped == true {
                expireLocked()
            }
            if let node = queue.popLast() {
                busy += 1
                let known = node.inode
                lock.unlock()
                var inode = known
                if inode == 0 {
                    var info = Darwin.stat()
                    if lstat(node.path, &info) == 0 { inode = UInt64(info.st_ino) }
                }
                lock.lock()
                if abandoned {
                    busy -= 1
                    lock.unlock()
                    return
                }
                if inode != 0, !seen.insert(inode).inserted {
                    node.fileBytes = 0
                    finish(node)
                    busy -= 1
                    lock.unlock()
                    continue
                }
                lock.unlock()
                let listed = list(node.path, device: device, walk: self)
                lock.lock()
                if abandoned {
                    busy -= 1
                    lock.unlock()
                    return
                }
                node.fileBytes += listed.files
                if !listed.readable { node.complete = false }
                if shouldStopLocked() || node.depth >= 48 {
                    node.complete = false
                    finish(node)
                    if shouldStopLocked() { expireLocked() }
                } else {
                    node.waiting = listed.dirs.count
                    if listed.dirs.isEmpty {
                        finish(node)
                    } else {
                        for dir in listed.dirs {
                            let child = Dir(name: dir.name, path: dir.path, fileBytes: dir.bytes, depth: node.depth + 1)
                            child.inode = dir.inode
                            child.parent = node
                            retained.append(child)
                            queue.append(child)
                        }
                    }
                }
                busy -= 1
                lock.unlock()
            } else if busy == 0 {
                lock.unlock()
                return
            } else {
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
    }

    private func shouldStopLocked() -> Bool {
        stopping || abandoned || Date() >= deadline || control?.isStopped == true
    }

    private func expireLocked() {
        let dropped = queue
        queue.removeAll()
        for node in dropped {
            node.complete = false
            finish(node)
        }
    }

    private func finish(_ node: Dir) {
        if node.sealed { return }
        node.sealed = true
        if node.name.hasSuffix(".app") {
            node.folded += node.kids.reduce(UInt64(0)) { $0 + $1.bytes }
            node.kids.removeAll()
        }
        node.bytes = node.fileBytes + node.folded + node.kids.reduce(UInt64(0)) { $0 + $1.bytes }
        guard let parent = node.parent else {
            finished = node
            return
        }
        parent.kids.append(node)
        if parent.kids.count > AllocatedSize.keptChildren {
            parent.kids.sort { $0.bytes < $1.bytes }
            let dropped = parent.kids.removeFirst()
            parent.folded += dropped.bytes
        }
        parent.waiting -= 1
        if parent.waiting == 0 {
            finish(parent)
        }
    }

    private func convert(_ node: Dir) -> AllocatedSize.Entry {
        let kids = node.kids.sorted { $0.bytes > $1.bytes }.map(convert)
        let hidden = node.folded + node.fileBytes
        var children = kids.filter { $0.bytes > 0 }
        let meaningful = hidden >= 1_048_576 || (node.bytes >= 50 && hidden >= node.bytes / 50)
        if meaningful, !children.isEmpty {
            children.append(AllocatedSize.Entry(
                name: L("其他"),
                path: node.path + "#other",
                bytes: hidden,
                complete: node.complete,
                children: []
            ))
        }
        return AllocatedSize.Entry(
            name: node.name,
            path: node.path,
            bytes: node.bytes,
            complete: node.complete,
            children: children
        )
    }
}
