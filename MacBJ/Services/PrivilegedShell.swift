import Darwin
import Foundation
import Security

/// 由泊位进程自己向系统要管理员权限。授权框上的名字来自调用进程，而不是 osascript。
nonisolated enum PrivilegedShell {
    struct Outcome: Sendable {
        var cancelled: Bool
        var status: Int32
        var text: String
    }

    private typealias ExecutePrivileges = @convention(c) (
        AuthorizationRef,
        UnsafePointer<CChar>,
        AuthorizationFlags,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
        UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
    ) -> OSStatus

    nonisolated static func run(_ shell: String) -> Outcome {
        var auth: AuthorizationRef?
        let created = AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights], &auth)
        guard created == errAuthorizationSuccess, let auth else {
            return Outcome(cancelled: false, status: created, text: "")
        }
        defer { AuthorizationFree(auth, [.destroyRights]) }
        guard let execute = loadExecute() else {
            return Outcome(cancelled: false, status: errAuthorizationInternal, text: "")
        }

        let script = shell + "\nprintf '\\n__MACBJ_STATUS__:%d\\n' $?"
        let dashC = strdup("-c")
        let body = strdup(script)
        defer {
            free(dashC)
            free(body)
        }
        guard let dashC, let body else {
            return Outcome(cancelled: false, status: errAuthorizationInternal, text: "")
        }

        var pipe: UnsafeMutablePointer<FILE>?
        let status: OSStatus = "/bin/zsh".withCString { tool in
            var argv: [UnsafeMutablePointer<CChar>?] = [dashC, body, nil]
            return argv.withUnsafeMutableBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return errAuthorizationInternal }
                return execute(auth, tool, [], base, &pipe)
            }
        }
        if status == errAuthorizationCanceled || status == errAuthorizationDenied {
            return Outcome(cancelled: true, status: status, text: "")
        }
        let output = read(pipe)
        let parsed = splitStatus(output)
        if status != errAuthorizationSuccess {
            return Outcome(cancelled: false, status: status, text: parsed.text)
        }
        return Outcome(cancelled: false, status: parsed.status, text: parsed.text)
    }

    private nonisolated static func loadExecute() -> ExecutePrivileges? {
        guard let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW),
              let symbol = dlsym(handle, "AuthorizationExecuteWithPrivileges") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ExecutePrivileges.self)
    }

    private nonisolated static func read(_ pipe: UnsafeMutablePointer<FILE>?) -> String {
        guard let pipe else { return "" }
        defer { fclose(pipe) }
        var collected = ""
        var buffer = [CChar](repeating: 0, count: 4096)
        while fgets(&buffer, Int32(buffer.count), pipe) != nil {
            collected += String(cString: buffer)
        }
        return collected
    }

    private nonisolated static func splitStatus(_ output: String) -> (status: Int32, text: String) {
        let marker = "__MACBJ_STATUS__:"
        guard let range = output.range(of: marker, options: .backwards) else {
            return (1, output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let code = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let text = String(output[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (Int32(code) ?? 1, text)
    }
}
