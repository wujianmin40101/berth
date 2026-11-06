import Foundation

nonisolated struct NodeProvider: RuntimeProvider {
    var kind: RuntimeKind { .node }

    func catalog(mirror: MirrorChoice) async -> RuntimeSnapshot {
        await Task.detached(priority: .userInitiated) {
            let output = await Shell.run(RuntimeScripts.inspect(.node))
            let probe = ProbeText.parse(output.stdout)
            let installed = NodeListing.versions(backend: probe.backend, list: probe.list)
            let remote = await NodeIndex.fetch(mirror)
            let releases = (remote ?? []).map {
                RuntimeVersion(
                    name: $0.version,
                    isCurrent: false,
                    isInstalled: false,
                    channel: $0.channel,
                    releasedOn: $0.releasedOn,
                    npm: $0.npm,
                    v8: $0.v8
                )
            }
            let versions = CatalogMerge.combining(installed: installed, remote: releases) {
                NodeIndex.channel(of: $0, in: remote ?? [])
            }
            let loadError = (output.status != 0 && installed.isEmpty) ? ShellMessage.display(output.stderr) : nil
            return RuntimeSnapshot(
                kind: .node,
                backend: probe.backend,
                versions: versions,
                loadError: loadError,
                remoteFailed: remote == nil && probe.backend.canSwitch
            )
        }.value
    }

    func installScript(backend: RuntimeBackend, version: String, mirror: MirrorChoice) -> String? {
        guard backend.canSwitch, version != "system", let quoted = VersionToken.shellQuoted(version) else {
            return nil
        }
        let prefix = MirrorScript.prefix(kind: .node, backend: backend, mirror: mirror)
        switch backend {
        case .fnm:
            return prefix + "fnm install \(quoted)"
        case .nvm:
            return prefix + NvmScript.wrapping("nvm install \(quoted)")
        case .volta:
            let bare = VersionOrder.key(version)
            guard VersionToken.validated(bare) != nil else { return nil }
            return prefix + "volta install 'node@\(bare)'"
        default:
            return nil
        }
    }

    func uninstallScript(backend: RuntimeBackend, version: String) -> String? {
        guard backend.canSwitch, version != "system", let quoted = VersionToken.shellQuoted(version) else {
            return nil
        }
        switch backend {
        case .fnm:
            return "fnm uninstall \(quoted)"
        case .nvm:
            return NvmScript.wrapping("nvm uninstall \(quoted)")
        case .volta:
            let bare = VersionOrder.key(version)
            guard VersionToken.validated(bare) != nil else { return nil }
            return """
            image="${VOLTA_HOME:-$HOME/.volta}/tools/image/node/\(bare)"
            case "$image" in
              "$HOME"/.volta/tools/image/node/*) rm -rf "$image" ;;
              *) echo \(ShellLiteral.singleQuoted(L("拒绝删除意外路径。"))) >&2; exit 1 ;;
            esac
            """
        default:
            return nil
        }
    }

    func setGlobalScript(backend: RuntimeBackend, version: String) -> String? {
        RuntimeScripts.activate(.node, backend: backend, version: version)
    }

    func projectPin(in directory: URL) -> ProjectPin? {
        ProjectPins.read(kind: .node, in: directory)
    }

    func writeProjectPin(_ version: String, in directory: URL) throws {
        try ProjectPins.write(kind: .node, version: version, in: directory)
    }

    func aliases(backend: RuntimeBackend) async -> [VersionAlias] {
        switch backend {
        case .nvm:
            let output = await Shell.run(NvmScript.wrapping("nvm alias"))
            return AliasListing.parseArrowList(output.stdout)
        case .fnm:
            let output = await Shell.run("fnm alias")
            return AliasListing.parseArrowList(output.stdout)
        case .volta, .missing:
            return AliasTable.load(kind: .node, from: AliasTable.fileURL())
        case .pyenv, .uv, .official:
            return []
        }
    }

    func setAlias(name: String, version: String, backend: RuntimeBackend) async throws {
        switch backend {
        case .nvm:
            guard let script = Self.aliasScript(backend: backend, name: name, version: version) else {
                throw RuntimeFailure(message: L("别名或版本号不能使用。default 请用「设为全局默认」。"))
            }
            try await ShellCommand.succeed(script)
        case .fnm:
            guard let script = Self.aliasScript(backend: backend, name: name, version: version) else {
                throw RuntimeFailure(message: L("别名或版本号不能使用。default 请用「设为全局默认」。"))
            }
            try await ShellCommand.succeed(script)
        case .volta, .missing:
            try AliasTable.upsert(kind: .node, name: name, version: version, at: AliasTable.fileURL())
        case .pyenv, .uv, .official:
            throw RuntimeFailure(message: L("这个 Node 管理器不能保存别名。"))
        }
    }

    static func aliasScript(backend: RuntimeBackend, name: String, version: String) -> String? {
        guard let name = AliasName.validated(name), let version = VersionToken.shellQuoted(version) else {
            return nil
        }
        switch backend {
        case .nvm:
            return NvmScript.wrapping("nvm alias '\(name)' \(version)")
        case .fnm:
            return "fnm alias \(version) '\(name)'"
        default:
            return nil
        }
    }

    func removeAlias(name: String, backend: RuntimeBackend) async throws {
        guard let name = AliasName.validated(name) else {
            throw RuntimeFailure(message: L("这个别名不能删除。"))
        }
        switch backend {
        case .nvm:
            try await ShellCommand.succeed(NvmScript.wrapping("nvm unalias '\(name)'"))
        case .fnm:
            try await ShellCommand.succeed("fnm unalias '\(name)'")
        case .volta, .missing:
            try AliasTable.remove(kind: .node, name: name, at: AliasTable.fileURL())
        case .pyenv, .uv, .official:
            throw RuntimeFailure(message: L("这个 Node 管理器不能删除别名。"))
        }
    }
}
