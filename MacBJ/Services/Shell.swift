import Darwin
import Foundation
import os

/// 图形界面进程拿不到终端的 PATH，nvm 也只是 shell 函数。
/// 用登录且交互的 zsh 执行，才能读到用户在 .zshrc 里配置的版本管理器。
nonisolated enum Shell {
    struct Output: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    private static let log = Logger(subsystem: "app.macbj.desktop", category: "shell")

    @concurrent
    static func run(
        _ script: String,
        timeout: TimeInterval = 25,
        login: Bool = true,
        handle: ShellHandle? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async -> Output {
        let control = handle?.control ?? ShellControl()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: execute(
                        script,
                        timeout: timeout,
                        login: login,
                        control: control,
                        onOutput: onOutput
                    ))
                }
            }
        } onCancel: {
            control.cancel()
        }
    }

    /// 在普通线程里等进程结束。`DispatchGroup.wait` 不能写在 async 函数里。
    private static func execute(
        _ script: String,
        timeout: TimeInterval,
        login: Bool,
        control: ShellControl,
        onOutput: (@Sendable (String) -> Void)?
    ) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = login ? ["-lic", script] : ["-c", script]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["CLICOLOR"] = "0"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = OutputBuffer()
        let stderr = OutputBuffer()
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            stdout.add(text, onOutput: onOutput)
        }
        stderrHandle.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            stderr.add(text, onOutput: onOutput)
        }

        do {
            try process.run()
        } catch {
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            return Output(status: 1, stdout: "", stderr: error.localizedDescription)
        }
        control.store(process)

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if control.isCancelled {
                let killDeadline = Date().addingTimeInterval(1.2)
                while process.isRunning && Date() < killDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                break
            }
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning && !control.isCancelled {
            process.waitUntilExit()
        }

        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        if !process.isRunning {
            stdout.add(String(decoding: stdoutHandle.readDataToEndOfFile(), as: UTF8.self), onOutput: onOutput)
            stderr.add(String(decoding: stderrHandle.readDataToEndOfFile(), as: UTF8.self), onOutput: onOutput)
        }

        let output = Output(
            status: timedOut ? 124 : (control.isCancelled ? 130 : process.terminationStatus),
            stdout: stdout.text,
            stderr: timedOut ? "命令超时。" : stderr.text
        )
        if output.status != 0 {
            log.error("command failed, status \(output.status, privacy: .public)")
        }
        return output
    }
}

/// 安装和卸载把这个句柄交给界面。点取消时直接停掉进程树，不依赖任务取消有没有传进 `zsh`。
nonisolated final class ShellHandle: @unchecked Sendable {
    fileprivate let control = ShellControl()

    func cancel() {
        control.cancel()
    }

    var isCancelled: Bool { control.isCancelled }
}

/// `Process` 不能放进 `Mutex`。取消和进程句柄都留在这一个锁里。
nonisolated private final class ShellControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func store(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldStop = cancelled
        lock.unlock()
        if shouldStop {
            Self.terminateTree(process.processIdentifier)
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let pid = process?.processIdentifier
        lock.unlock()
        guard let pid else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            Self.terminateTree(pid)
        }
    }

    /// `zsh -lic` 下面还有 curl 或安装脚本。只向 shell 发 SIGTERM 时，子进程会继续跑，界面就像没点到取消。
    private static func terminateTree(_ pid: Int32, depth: Int = 0) {
        guard pid > 1, depth < 8 else { return }
        for child in directChildren(pid) {
            terminateTree(child, depth: depth + 1)
        }
        kill(pid, SIGKILL)
    }

    private static func directChildren(_ pid: Int32) -> [Int32] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", String(pid)]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(whereSeparator: \.isNewline).compactMap { Int32($0) }.filter { $0 > 1 && $0 != pid }
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

nonisolated private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ""

    func add(_ text: String, onOutput: (@Sendable (String) -> Void)?) {
        guard !text.isEmpty else { return }
        lock.lock()
        value += text
        lock.unlock()
        onOutput?(text)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
