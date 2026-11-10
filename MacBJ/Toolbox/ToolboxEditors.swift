import Darwin
import Foundation
import Security

enum HostsFile {
    static func read() -> Result<String, ToolError> {
        do {
            return .success(try String(contentsOf: URL(fileURLWithPath: "/etc/hosts"), encoding: .utf8))
        } catch {
            return .failure(ToolError(L("没有读到 /etc/hosts。")))
        }
    }

    /// 返回第一条需要先改的问题。通过时是 nil。
    static func problem(in text: String) -> String? {
        var sawLocalhost = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2 else { return L("这一行缺少主机名：%@", line) }
            guard isIPAddress(parts[0]) else { return L("无法识别的地址：%@", parts[0]) }
            for name in parts.dropFirst() {
                if name.hasPrefix("#") { break }
                guard isHostname(name) else { return L("无法识别的主机名：%@", name) }
                if name == "localhost" { sawLocalhost = true }
            }
        }
        if !sawLocalhost { return L("需要保留 localhost 这一行。") }
        return nil
    }

    static func isIPAddress(_ value: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &v4) == 1 }
            || value.withCString { inet_pton(AF_INET6, $0, &v6) == 1 }
    }

    static func isHostname(_ value: String) -> Bool {
        guard (1...253).contains(value.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) } && !value.hasPrefix(".") && !value.hasSuffix(".")
    }

    static func backup(_ text: String) {
        try? text.write(to: ToolboxPaths.file("hosts.backup"), atomically: true, encoding: .utf8)
    }

    static func install(_ text: String) async -> String? {
        if let problem = problem(in: text) { return problem }
        let proposed = ToolboxPaths.file("hosts.proposed")
        do {
            try text.write(to: proposed, atomically: true, encoding: .utf8)
        } catch {
            return L("没有写好准备替换的文件。")
        }
        let path = proposed.path
        let command = "cp /etc/hosts /etc/hosts.macbj-bak && cp \(ShellQuote.singleQuoted(path)) /etc/hosts"
        let detail: String? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let outcome = PrivilegedShell.run(command)
                if outcome.cancelled {
                    continuation.resume(returning: L("已取消写入。"))
                    return
                }
                if outcome.status == 0 {
                    continuation.resume(returning: nil)
                    return
                }
                if outcome.status == errAuthorizationInternal {
                    continuation.resume(returning: L("没有打开系统授权。"))
                    return
                }
                continuation.resume(returning: outcome.text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        guard let detail else { return nil }
        if detail.localizedCaseInsensitiveContains("cancel") || detail.contains(L("取消")) {
            return L("已取消写入。")
        }
        return detail.isEmpty ? L("没有写入 /etc/hosts。") : detail
    }

    /// 读管道的线程先进入 `read`，再启动进程。否则授权框或报错写满管道后，进程会停住。
    static func collect(executable: String, arguments: [String]) -> (status: Int32, text: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let group = DispatchGroup()
        let collected = PipeText()
        group.enter()
        Thread {
            collected.append(output.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }.start()
        group.enter()
        Thread {
            collected.append(errors.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }.start()
        do {
            try process.run()
        } catch {
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            group.wait()
            return (-1, "")
        }
        process.waitUntilExit()
        group.wait()
        return (process.terminationStatus, String(decoding: collected.data, as: UTF8.self))
    }
}

private final class PipeText: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ next: Data) {
        lock.lock()
        storage.append(next)
        lock.unlock()
    }
}

enum ProxyDraft {
    static func problem(in value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        guard text.count < 200, ShellQuote.isSingleLine(text) else { return L("代理地址太长，或者包含换行。") }
        let blocked = CharacterSet(charactersIn: "'\"`;$|&<>\\")
        if text.unicodeScalars.contains(where: { blocked.contains($0) || $0.value < 32 }) {
            return L("代理地址里有不能用在终端环境变量里的字符。")
        }
        return nil
    }

    /// 只保留填了、并且能放进环境变量的地址。空值不写入，避免清掉服务自己的代理。
    static func serviceEnvironment(http: String, https: String, all: String, bypass: String) -> Result<[String: String], ToolError> {
        let pairs = [
            ("http_proxy", http),
            ("https_proxy", https),
            ("ALL_PROXY", all),
            ("NO_PROXY", bypass),
        ]
        var values: [String: String] = [:]
        for (key, raw) in pairs {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if let problem = problem(in: text) {
                return .failure(ToolError(problem))
            }
            values[key] = text
        }
        return .success(values)
    }
}

enum EnvName {
    static func problem(in name: String) -> String? {
        guard name.wholeMatch(of: /^[A-Za-z_][A-Za-z0-9_]*$/) != nil else {
            return L("变量名只能用字母、数字和下划线，并且不能以数字开头。")
        }
        return nil
    }
}

enum DevTransforms {
    static func formatJSON(_ text: String, pretty: Bool) -> Result<String, ToolError> {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .failure(ToolError(L("这不是有效的 JSON。")))
        }
        let options: JSONSerialization.WritingOptions = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        guard let output = try? JSONSerialization.data(withJSONObject: object, options: options),
              var text = String(data: output, encoding: .utf8) else {
            return .failure(ToolError(L("没有格式化这份 JSON。")))
        }
        if pretty == false {
            text = text.replacingOccurrences(of: "\n", with: "")
        }
        return .success(text)
    }

    static func timestamp(_ text: String) -> Result<String, ToolError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Double(trimmed), raw >= 0 else { return .failure(ToolError(L("需要一个 Unix 时间戳。"))) }
        let seconds = raw > 100_000_000_000 ? raw / 1000 : raw
        let date = Date(timeIntervalSince1970: seconds)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return .success(formatter.string(from: date))
    }

    static func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func base64Decode(_ text: String) -> Result<String, ToolError> {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: cleaned), let decoded = String(data: data, encoding: .utf8) else {
            return .failure(ToolError(L("这不是 UTF-8 的 Base64。")))
        }
        return .success(decoded)
    }

    static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    static func urlDecode(_ text: String) -> Result<String, ToolError> {
        guard let decoded = text.removingPercentEncoding else { return .failure(ToolError(L("没有解码这份文本。"))) }
        return .success(decoded)
    }
}
