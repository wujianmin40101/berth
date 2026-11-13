import Foundation

/// USB MJPEG 预览。只在画面页开着时采集；刷新只重开这条流，不走控制通道的截图。
nonisolated enum PhonePreviewSignal: Sendable {
    case waiting
    case unavailable
}

nonisolated enum PhonePreviewLaunch {
    static func nodeBinary() -> String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// 和 iPhone Use 的预览进程同一条命令。设备标识只放进进程参数，不返回给界面。
    static func command(stateDir: URL, checkout: URL, node: String) -> [String]? {
        guard FileManager.default.isExecutableFile(atPath: node) else { return nil }
        guard let config = try? Data(contentsOf: stateDir.appendingPathComponent("config.json")),
              let body = try? JSONSerialization.jsonObject(with: config) as? [String: Any],
              let udid = body["udid"] as? String,
              udid.range(of: #"^[A-Za-z0-9-]{8,64}$"#, options: .regularExpression) != nil else { return nil }
        let port = body["mjpeg_device_port"] as? Int ?? 9100
        guard (1024...65535).contains(port) else { return nil }
        let runtime = stateDir.appendingPathComponent("runtime/forward", isDirectory: true)
        guard FileManager.default.fileExists(atPath: runtime.appendingPathComponent("node_modules/appium-ios-device").path) else { return nil }
        let source = checkout.appendingPathComponent("tooling/screen-stream.mjs")
        guard let sourceBytes = try? Data(contentsOf: source), !sourceBytes.isEmpty else { return nil }
        let target = runtime.appendingPathComponent("screen-stream.mjs")
        if (try? Data(contentsOf: target)) != sourceBytes {
            let temporary = runtime.appendingPathComponent(".screen-stream-\(UUID().uuidString)")
            do {
                try sourceBytes.write(to: temporary, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                if FileManager.default.fileExists(atPath: target.path) {
                    _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: target)
                }
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                return nil
            }
        }
        return [node, target.path, udid, String(port)]
    }
}

nonisolated final class PhoneFrameBuffer: @unchecked Sendable {
    private let limit = 4 * 1024 * 1024
    private var buffer = Data()
    private let lock = NSLock()

    func feed(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        var frames: [Data] = []
        var incoming = chunk
        while !incoming.isEmpty {
            if limit - buffer.count <= 0 {
                buffer = buffer.last == 0xFF ? Data([0xFF]) : Data()
            }
            let take = min(limit - buffer.count, incoming.count, 65_536)
            guard take > 0 else { break }
            buffer.append(incoming.prefix(take))
            incoming.removeFirst(take)
            while !buffer.isEmpty {
                guard let start = buffer.range(of: Data([0xFF, 0xD8])) else {
                    buffer = buffer.last == 0xFF ? Data([0xFF]) : Data()
                    break
                }
                if start.lowerBound > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<start.lowerBound)
                }
                guard let searchStart = buffer.index(buffer.startIndex, offsetBy: 2, limitedBy: buffer.endIndex),
                      searchStart < buffer.endIndex,
                      let end = buffer.range(of: Data([0xFF, 0xD9]), in: searchStart..<buffer.endIndex) else { break }
                let raw = buffer.subdata(in: buffer.startIndex..<end.upperBound)
                buffer.removeSubrange(buffer.startIndex..<end.upperBound)
                if Self.dimensions(raw) != nil {
                    frames.append(raw)
                }
            }
        }
        return frames
    }

    static func dimensions(_ raw: Data) -> (width: Int, height: Int)? {
        guard raw.count >= 4, raw[raw.startIndex] == 0xFF, raw[raw.index(after: raw.startIndex)] == 0xD8 else { return nil }
        let sof: Set<UInt8> = [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]
        var offset = 2
        while offset + 1 < raw.count {
            if raw[offset] != 0xFF { return nil }
            while offset < raw.count, raw[offset] == 0xFF { offset += 1 }
            if offset >= raw.count { return nil }
            let marker = raw[offset]
            offset += 1
            if marker == 0xD9 || marker == 0xDA { return nil }
            if marker == 0x01 || (0xD0...0xD8).contains(marker) { continue }
            if offset + 2 > raw.count { return nil }
            let length = (Int(raw[offset]) << 8) | Int(raw[offset + 1])
            if length < 2 || offset + length > raw.count { return nil }
            if sof.contains(marker) {
                if length < 8 { return nil }
                let height = (Int(raw[offset + 3]) << 8) | Int(raw[offset + 4])
                let width = (Int(raw[offset + 5]) << 8) | Int(raw[offset + 6])
                guard width > 0, width <= 16_384, height > 0, height <= 16_384 else { return nil }
                return (width, height)
            }
            offset += length
        }
        return nil
    }
}

nonisolated final class PhonePreview: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false

    func stop() {
        lock.lock()
        stopped = true
        let running = process
        lock.unlock()
        if let running, running.isRunning {
            running.terminate()
        }
    }

    func run(
        stateDir: URL,
        checkout: URL,
        onFrame: @escaping @Sendable (Data) -> Void,
        onSignal: @escaping @Sendable (PhonePreviewSignal) -> Void
    ) async {
        begin()
        var pause: UInt64 = 500_000_000
        while !Task.isCancelled && !isStopped {
            let held = await Task.detached { [self] in
                self.capture(stateDir: stateDir, checkout: checkout, onFrame: onFrame, onSignal: onSignal)
            }.value
            if Task.isCancelled || isStopped { break }
            pause = held ? 500_000_000 : min(pause &* 2, 2_000_000_000)
            try? await Task.sleep(nanoseconds: pause)
        }
        stop()
    }

    private func begin() {
        lock.lock()
        stopped = false
        lock.unlock()
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    private func capture(
        stateDir: URL,
        checkout: URL,
        onFrame: @escaping @Sendable (Data) -> Void,
        onSignal: @escaping @Sendable (PhonePreviewSignal) -> Void
    ) -> Bool {
        guard let node = PhonePreviewLaunch.nodeBinary(),
              let command = PhonePreviewLaunch.command(stateDir: stateDir, checkout: checkout, node: node) else {
            onSignal(.unavailable)
            return false
        }
        let runtime = stateDir.appendingPathComponent("runtime/forward", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command[0])
        process.arguments = Array(command.dropFirst())
        process.currentDirectoryURL = runtime
        process.qualityOfService = .userInitiated
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        let parser = PhoneFrameBuffer()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { file in
            let data = file.availableData
            if data.isEmpty {
                file.readabilityHandler = nil
                return
            }
            for frame in parser.feed(data) {
                onFrame(frame)
            }
        }
        defer {
            handle.readabilityHandler = nil
            lock.lock()
            if self.process === process { self.process = nil }
            lock.unlock()
        }
        lock.lock()
        if stopped {
            lock.unlock()
            return false
        }
        self.process = process
        lock.unlock()
        let started = Date()
        do {
            try process.run()
        } catch {
            onSignal(.unavailable)
            return false
        }
        lock.lock()
        let halt = stopped
        lock.unlock()
        if halt {
            if process.isRunning { process.terminate() }
            return false
        }
        onSignal(.waiting)
        process.waitUntilExit()
        return Date().timeIntervalSince(started) > 1
    }
}
