import Foundation

nonisolated struct PythonProvider: RuntimeProvider {
    var kind: RuntimeKind { .python }

    func catalog(mirror: MirrorChoice) async -> RuntimeSnapshot {
        let provider = self
        return await Task.detached(priority: .userInitiated) {
            let output = await Shell.run(RuntimeScripts.inspect(.python))
            let probe = ProbeText.parse(output.stdout)
            let installed = PythonListing.versions(backend: probe.backend, global: probe.global, list: probe.list)
            let remote = await provider.remoteOfferings(backend: probe.backend)
            let versions = CatalogMerge.combining(installed: installed, remote: remote.offerings) {
                PythonReleaseTable.channel(for: $0)
            }
            let loadError = (output.status != 0 && installed.isEmpty) ? ShellMessage.display(output.stderr) : nil
            return RuntimeSnapshot(
                kind: .python,
                backend: probe.backend,
                versions: versions,
                loadError: loadError,
                remoteFailed: remote.failed && probe.backend.canSwitch
            )
        }.value
    }

    func installScript(backend: RuntimeBackend, version: String, mirror: MirrorChoice) -> String? {
        guard backend.canSwitch, version != "system", let quoted = VersionToken.shellQuoted(version) else {
            return nil
        }
        let prefix = MirrorScript.prefix(kind: .python, backend: backend, mirror: mirror)
        switch backend {
        case .pyenv:
            return prefix + "pyenv install \(quoted)"
        case .uv:
            return prefix + "uv python install \(quoted)"
        default:
            return nil
        }
    }

    func uninstallScript(backend: RuntimeBackend, version: String) -> String? {
        guard backend.canSwitch, version != "system", let quoted = VersionToken.shellQuoted(version) else {
            return nil
        }
        switch backend {
        case .pyenv:
            return "pyenv uninstall -f \(quoted)"
        case .uv:
            return "uv python uninstall \(quoted)"
        default:
            return nil
        }
    }

    func setGlobalScript(backend: RuntimeBackend, version: String) -> String? {
        RuntimeScripts.activate(.python, backend: backend, version: version)
    }

    func projectPin(in directory: URL) -> ProjectPin? {
        ProjectPins.read(kind: .python, in: directory)
    }

    func writeProjectPin(_ version: String, in directory: URL) throws {
        try ProjectPins.write(kind: .python, version: version, in: directory)
    }

    func aliases(backend: RuntimeBackend) async -> [VersionAlias] {
        switch backend {
        case .pyenv, .uv, .missing:
            return AliasTable.load(kind: .python, from: AliasTable.fileURL())
        case .fnm, .nvm, .volta, .official:
            return []
        }
    }

    func setAlias(name: String, version: String, backend: RuntimeBackend) async throws {
        switch backend {
        case .pyenv, .uv, .missing:
            try AliasTable.upsert(kind: .python, name: name, version: version, at: AliasTable.fileURL())
        case .fnm, .nvm, .volta, .official:
            throw RuntimeFailure(message: "这个 Python 管理器不能保存别名。")
        }
    }

    func removeAlias(name: String, backend: RuntimeBackend) async throws {
        switch backend {
        case .pyenv, .uv, .missing:
            try AliasTable.remove(kind: .python, name: name, at: AliasTable.fileURL())
        case .fnm, .nvm, .volta, .official:
            throw RuntimeFailure(message: "这个 Python 管理器不能删除别名。")
        }
    }

    private func remoteOfferings(backend: RuntimeBackend) async -> (offerings: [RuntimeVersion], failed: Bool) {
        let script: String? = switch backend {
        case .pyenv: "pyenv install --list"
        case .uv: "uv python list"
        default: nil
        }
        guard let script else { return ([], false) }
        let output = await Shell.run(script, timeout: 40)
        guard output.status == 0 else { return ([], true) }
        return (PythonRemoteList.offerings(from: output.stdout), false)
    }
}
