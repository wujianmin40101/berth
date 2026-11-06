import Foundation

nonisolated struct RuntimeFailure: Error, Equatable, Sendable {
    var message: String
}

nonisolated struct ProbeText: Equatable, Sendable {
    var backend: RuntimeBackend
    var global: String
    var list: String

    static func parse(_ output: String) -> ProbeText {
        let lines = output.strippingTerminalFormatting().lines
        var backend = RuntimeBackend.missing
        var globalLines: [String] = []
        var listLines: [String] = []
        var readingGlobal = false

        for line in lines {
            if line.hasPrefix("__BACKEND__ ") {
                backend = RuntimeBackend(marker: String(line.dropFirst("__BACKEND__ ".count)))
                continue
            }
            if line == "__GLOBAL__" || line.hasPrefix("__GLOBAL__ ") {
                readingGlobal = true
                let inline = line.dropFirst("__GLOBAL__".count).trimmingCharacters(in: .whitespaces)
                if !inline.isEmpty {
                    globalLines.append(inline)
                }
                continue
            }
            if line == "__LIST__" {
                readingGlobal = false
                continue
            }
            if readingGlobal {
                globalLines.append(line)
            } else {
                listLines.append(line)
            }
        }

        return ProbeText(
            backend: backend,
            global: globalLines.joined(separator: "\n"),
            list: listLines.joined(separator: "\n")
        )
    }
}

nonisolated enum ProviderRegistry {
    static func provider(for kind: RuntimeKind) -> any RuntimeProvider {
        switch kind {
        case .node: NodeProvider()
        case .python: PythonProvider()
        case .go, .java, .rust: OfficialProvider(kind: kind)
        }
    }
}

nonisolated enum ShellCommand {
    static func succeed(
        _ script: String,
        timeout: TimeInterval = 25,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws {
        let output = await Shell.run(script, timeout: timeout, onOutput: onOutput)
        guard output.status == 0 else {
            let message = ShellMessage.display(output.stderr.isEmpty ? output.stdout : output.stderr)
            throw RuntimeFailure(message: message.isEmpty ? "命令没有成功。" : message)
        }
    }
}

nonisolated enum MirrorScript {
    static func prefix(kind: RuntimeKind, backend: RuntimeBackend, mirror: MirrorChoice) -> String {
        guard mirror == .china else { return "" }
        switch (kind, backend) {
        case (.node, .nvm):
            return "export NVM_NODEJS_ORG_MIRROR='https://npmmirror.com/mirrors/node'\n"
        case (.node, .fnm):
            return "export FNM_NODE_DIST_MIRROR='https://npmmirror.com/mirrors/node'\n"
        case (.node, .volta):
            return "echo 'Volta 不使用国内镜像，这次仍从官方地址下载。' >&2\n"
        case (.python, .pyenv):
            return "export PYTHON_BUILD_MIRROR_URL='https://mirrors.tuna.tsinghua.edu.cn/python'\n"
        case (.python, .uv):
            return "export UV_PYTHON_INSTALL_MIRROR='https://registry.npmmirror.com/-/binary/python-build-standalone'\n"
        default:
            return ""
        }
    }
}

nonisolated enum NvmScript {
    static func wrapping(_ body: String) -> String {
        """
        if ! command -v nvm >/dev/null 2>&1; then
          . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
        fi
        \(body)
        """
    }
}

nonisolated enum ShellMessage {
    static func display(_ text: String) -> String {
        let lines = text.lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let joined = lines.suffix(6).joined(separator: "\n")
        guard joined.count > 500 else { return joined }
        return String(joined.suffix(500))
    }
}
