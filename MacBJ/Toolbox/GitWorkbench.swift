import Foundation

struct GitSnapshot: Equatable, Sendable {
    var name = ""
    var email = ""
    var proxy = ""
    var aliases: [String] = []
    var publicKey = ""
}

enum GitWorkbench {
    static func load() async -> GitSnapshot {
        let output = await Shell.run(
            """
            git config --global --get user.name | sed 's/^/name=/'
            git config --global --get user.email | sed 's/^/email=/'
            git config --global --get http.proxy | sed 's/^/proxy=/'
            git config --global --get-regexp '^alias\\.' | sed 's/^/alias=/'
            if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then cat "$HOME/.ssh/id_ed25519.pub" | sed 's/^/key=/'; fi
            """,
            timeout: 20
        )
        var snapshot = GitSnapshot()
        for raw in output.stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if let value = line.dropPrefix("name=") { snapshot.name = value }
            else if let value = line.dropPrefix("email=") { snapshot.email = value }
            else if let value = line.dropPrefix("proxy=") { snapshot.proxy = value }
            else if let value = line.dropPrefix("alias=") { snapshot.aliases.append(value) }
            else if let value = line.dropPrefix("key=") { snapshot.publicKey = value }
        }
        return snapshot
    }

    static func save(name: String, email: String, proxy: String) async -> String? {
        for value in [name, email, proxy] where !ShellQuote.isSingleLine(value) {
            return L("不能包含换行。")
        }
        if let problem = ProxyDraft.problem(in: proxy) { return problem }
        let script = [
            assignment("user.name", name),
            assignment("user.email", email),
            assignment("http.proxy", proxy),
        ].joined(separator: "\n")
        return failure(of: await Shell.run(script, timeout: 20))
    }

    static func addAlias(name: String, command: String) async -> String? {
        guard name.wholeMatch(of: /^[A-Za-z][A-Za-z0-9-]*$/) != nil else {
            return L("别名只能用字母、数字和连字符。")
        }
        guard ShellQuote.isSingleLine(command), !command.trimmingCharacters(in: .whitespaces).isEmpty else {
            return L("别名对应的命令不能为空，也不能换行。")
        }
        let script = "git config --global alias.\(name) \(ShellQuote.singleQuoted(command))"
        return failure(of: await Shell.run(script, timeout: 20))
    }

    static func generateKey() async -> String? {
        let output = await Shell.run(
            """
            if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
              echo EXISTS
              exit 0
            fi
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "macbj"
            """,
            timeout: 20
        )
        if output.stdout.contains("EXISTS") {
            return L("已经有一把 ed25519 公钥，没有覆盖它。")
        }
        return failure(of: output)
    }

    private static func assignment(_ key: String, _ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "git config --global --unset \(key) || true"
        }
        return "git config --global \(key) \(ShellQuote.singleQuoted(trimmed))"
    }

    private static func failure(of output: Shell.Output) -> String? {
        guard output.status != 0 else { return nil }
        let detail = (output.stderr.isEmpty ? output.stdout : output.stderr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return detail.isEmpty ? L("Git 没有保存。") : detail
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
