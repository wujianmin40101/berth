import Foundation

/// 版本号会拼进 shell。只接受管理器自己的版本 token，拒绝空格和引号。
nonisolated enum VersionToken {
    static func validated(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.wholeMatch(of: /^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$/) != nil else {
            return nil
        }
        return value
    }

    static func shellQuoted(_ raw: String) -> String? {
        guard let value = validated(raw) else { return nil }
        return "'\(value)'"
    }
}

nonisolated enum RuntimeScripts {
    static func inspect(_ kind: RuntimeKind) -> String {
        switch kind {
        case .node: nodeInspect
        case .python: pythonInspect
        case .go, .java, .rust: OfficialScripts.inspect(kind)
        }
    }

    static func activate(
        _ kind: RuntimeKind,
        backend: RuntimeBackend,
        version: String
    ) -> String? {
        guard let quoted = VersionToken.shellQuoted(version),
              let version = VersionToken.validated(version) else {
            return nil
        }
        switch (kind, backend) {
        case (.node, .fnm):
            return "fnm default \(quoted)"
        case (.node, .nvm):
            return """
            if ! command -v nvm >/dev/null 2>&1; then
              . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
            fi
            nvm alias default \(quoted)
            """
        case (.node, .volta):
            return "volta install 'node@\(version)'"
        case (.python, .pyenv):
            return "pyenv global \(quoted)"
        case (.python, .uv):
            return "uv python pin --global \(quoted)"
        default:
            return nil
        }
    }

    private static let nodeInspect = """
    if command -v fnm >/dev/null 2>&1; then
      printf '%s\\n' '__BACKEND__ fnm'
      fnm list
    elif command -v nvm >/dev/null 2>&1 || [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
      if ! command -v nvm >/dev/null 2>&1; then
        . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
      fi
      printf '%s\\n' '__BACKEND__ nvm'
      nvm ls --no-colors
    elif command -v volta >/dev/null 2>&1; then
      printf '%s\\n' '__BACKEND__ volta'
      volta list node
    else
      printf '%s\\n' '__BACKEND__ none'
      if command -v node >/dev/null 2>&1; then
        node -v
      fi
    fi
    """

    private static let pythonInspect = """
    if command -v pyenv >/dev/null 2>&1; then
      printf '%s\\n' '__BACKEND__ pyenv'
      printf '%s\\n' '__GLOBAL__'
      pyenv global
      printf '%s\\n' '__LIST__'
      pyenv versions
    elif command -v uv >/dev/null 2>&1; then
      printf '%s\\n' '__BACKEND__ uv'
      printf '%s\\n' '__GLOBAL__'
      found=$(uv python find 2>/dev/null || true)
      printf '%s\\n' "$found"
      if [ -n "$found" ] && [ -x "$found" ]; then
        "$found" --version
      fi
      printf '%s\\n' '__LIST__'
      uv python list --only-installed
    else
      printf '%s\\n' '__BACKEND__ none'
      if command -v python3 >/dev/null 2>&1; then
        python3 --version
      fi
    fi
    """
}
