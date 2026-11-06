import Foundation

nonisolated enum ShellHook {
    static let begin = "# >>> macbj >>>"
    static let end = "# <<< macbj <<<"

    static let script = """
    \(begin)
    macbj_alias() {
      local runtime="$1" name="$2" file="$HOME/Library/Application Support/MacBJ/aliases.tsv"
      [ -f "$file" ] || return 1
      awk -v r="$runtime" -v n="$name" '$1 == r && $2 == n { print $3; found = 1; exit } END { exit !found }' "$file"
    }
    macbj_find_up() {
      local dir="$PWD" target="$1"
      while true; do
        if [ -f "$dir/$target" ]; then
          printf '%s\\n' "$dir/$target"
          return 0
        fi
        if [ "$dir" = "/" ]; then
          return 1
        fi
        dir=$(dirname "$dir")
      done
    }
    macbj_first_line() {
      sed -n '1{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}' "$1"
    }
    macbj_token() {
      case "$1" in
        ""|*[!A-Za-z0-9._+-]*|*..*) return 1 ;;
      esac
    }
    macbj_offpath() {
      local old="$1"
      [ -n "$old" ] || return 0
      PATH=":${PATH}:"
      PATH=${PATH//:$old:/:}
      PATH=${PATH#:}
      PATH=${PATH%:}
    }
    macbj_bind() {
      local kind="$1" pinname="$2" marker="$3"
      local root="$HOME/Library/Application Support/MacBJ/runtimes"
      local pin="" ver="" resolved="" prefix="" bin="" old=""
      if pin=$(macbj_find_up "$pinname"); then
        ver=$(macbj_first_line "$pin")
      fi
      if ! macbj_token "$ver"; then
        ver=$(awk -v k="$kind" '$1 == k { print $2; exit }' "$root/global.tsv" 2>/dev/null || true)
      fi
      resolved=$(macbj_alias "$kind" "$ver" 2>/dev/null || true)
      if macbj_token "$resolved"; then
        ver="$resolved"
      fi
      if ! macbj_token "$ver"; then
        ver=""
      fi
      case "$marker" in
        MACBJ_GO_BIN) old="${MACBJ_GO_BIN-}" ;;
        MACBJ_JAVA_BIN) old="${MACBJ_JAVA_BIN-}" ;;
        MACBJ_RUST_BIN) old="${MACBJ_RUST_BIN-}" ;;
        *) old="" ;;
      esac
      prefix="$root/$kind/$ver"
      case "$kind" in
        java) bin="$prefix/Contents/Home/bin" ;;
        *) bin="$prefix/bin" ;;
      esac
      if [ -n "$ver" ] && [ -d "$bin" ]; then
        if [ "$old" != "$bin" ]; then
          macbj_offpath "$old"
          export PATH="$bin:$PATH"
        fi
        case "$marker" in
          MACBJ_GO_BIN) typeset -g MACBJ_GO_BIN="$bin" ;;
          MACBJ_JAVA_BIN) typeset -g MACBJ_JAVA_BIN="$bin" ;;
          MACBJ_RUST_BIN) typeset -g MACBJ_RUST_BIN="$bin" ;;
        esac
        if [ "$kind" = "java" ]; then
          if [ "${MACBJ_JAVA_HELD-}" != "1" ] && [ "${MACBJ_JAVA_HELD-}" != "0" ]; then
            if [ -n "${JAVA_HOME+x}" ]; then
              typeset -g MACBJ_OLD_JAVA_HOME="$JAVA_HOME"
              typeset -g MACBJ_JAVA_HELD=1
            else
              typeset -g MACBJ_JAVA_HELD=0
            fi
          fi
          export JAVA_HOME="$prefix/Contents/Home"
        fi
      else
        macbj_offpath "$old"
        case "$marker" in
          MACBJ_GO_BIN) unset MACBJ_GO_BIN ;;
          MACBJ_JAVA_BIN) unset MACBJ_JAVA_BIN ;;
          MACBJ_RUST_BIN) unset MACBJ_RUST_BIN ;;
        esac
        if [ "$kind" = "java" ]; then
          case "${MACBJ_JAVA_HELD-}" in
            1) export JAVA_HOME="$MACBJ_OLD_JAVA_HOME" ;;
            0) unset JAVA_HOME ;;
          esac
          unset MACBJ_JAVA_HELD MACBJ_OLD_JAVA_HOME
        fi
      fi
    }
    macbj_chpwd() {
      local pin="" ver="" resolved="" key=""
      if pin=$(macbj_find_up .nvmrc) || pin=$(macbj_find_up .node-version); then
        ver=$(macbj_first_line "$pin")
        resolved=$(macbj_alias node "$ver" 2>/dev/null || true)
        [ -n "$resolved" ] && ver="$resolved"
        key="$ver"
      else
        key="__default__"
      fi
      if [ "$MACBJ_NODE" != "$key" ]; then
        typeset -g MACBJ_NODE="$key"
        if [ "$key" = "__default__" ]; then
          if command -v fnm >/dev/null 2>&1; then
            fnm use default >/dev/null 2>&1 || true
          elif command -v nvm >/dev/null 2>&1 || [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
            [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ] && . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
            nvm use default >/dev/null 2>&1 || true
          fi
        elif command -v fnm >/dev/null 2>&1; then
          fnm use "$ver"
        elif command -v nvm >/dev/null 2>&1 || [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ]; then
          [ -s "${NVM_DIR:-$HOME/.nvm}/nvm.sh" ] && . "${NVM_DIR:-$HOME/.nvm}/nvm.sh"
          nvm use "$ver"
        fi
      fi
      pin=""
      ver=""
      if pin=$(macbj_find_up .python-version); then
        ver=$(macbj_first_line "$pin")
        resolved=$(macbj_alias python "$ver" 2>/dev/null || true)
        [ -n "$resolved" ] && ver="$resolved"
        key="$ver"
      else
        key="__default__"
      fi
      if [ "$MACBJ_PY" != "$key" ]; then
        typeset -g MACBJ_PY="$key"
        if [ "$key" = "__default__" ]; then
          if command -v pyenv >/dev/null 2>&1; then
            pyenv shell --unset >/dev/null 2>&1 || true
          fi
          unset UV_PYTHON
        elif command -v pyenv >/dev/null 2>&1; then
          pyenv shell "$ver"
        elif command -v uv >/dev/null 2>&1; then
          export UV_PYTHON="$ver"
        fi
      fi
      macbj_bind go .go-version MACBJ_GO_BIN
      macbj_bind java .java-version MACBJ_JAVA_BIN
      macbj_bind rust .rust-version MACBJ_RUST_BIN
    }
    autoload -Uz add-zsh-hook
    add-zsh-hook chpwd macbj_chpwd
    macbj_chpwd
    \(end)
    """

    static func status(of existing: String) -> HookStatus {
        guard let block = block(in: existing) else { return .missing }
        return block == script ? .installed : .outdated
    }

    static func installing(into existing: String) -> String {
        if let range = blockRange(in: existing) {
            var updated = existing
            updated.replaceSubrange(range, with: script)
            if !updated.hasSuffix("\n") {
                updated.append("\n")
            }
            return updated
        }
        let trimmed = existing.trimmingCharacters(in: .newlines)
        if trimmed.isEmpty {
            return script + "\n"
        }
        return trimmed + "\n\n" + script + "\n"
    }

    static func apply(to zshrc: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: zshrc.path) {
            let backup = zshrc.deletingLastPathComponent().appending(path: zshrc.lastPathComponent + ".macbj-bak")
            if manager.fileExists(atPath: backup.path) {
                try manager.removeItem(at: backup)
            }
            try manager.copyItem(at: zshrc, to: backup)
        } else {
            try manager.createDirectory(at: zshrc.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let existing = (try? String(contentsOf: zshrc, encoding: .utf8)) ?? ""
        do {
            try installing(into: existing).write(to: zshrc, atomically: true, encoding: .utf8)
        } catch {
            throw RuntimeFailure(message: L("没有写入 shell 配置。"))
        }
    }

    static var userZshrc: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".zshrc")
    }

    private static func block(in existing: String) -> String? {
        guard let range = blockRange(in: existing) else { return nil }
        return String(existing[range])
    }

    private static func blockRange(in existing: String) -> Range<String.Index>? {
        guard let start = existing.range(of: begin),
              let endRange = existing.range(of: end, range: start.lowerBound..<existing.endIndex) else {
            return nil
        }
        return start.lowerBound..<endRange.upperBound
    }
}
