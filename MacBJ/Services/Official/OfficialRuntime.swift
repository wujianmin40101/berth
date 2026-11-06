import Foundation

nonisolated struct OfficialRelease: Equatable, Sendable {
    var version: String
    var channel: ReleaseChannel
    var sha256: String?
    var url: String
}

nonisolated enum OfficialURL {
    static func accepted(_ raw: String, kind: RuntimeKind) -> String? {
        guard !raw.contains("'"), !raw.contains("\n"), !raw.contains(" "),
              let url = URL(string: raw),
              url.scheme == "https",
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased() else {
            return nil
        }
        let path = url.path
        let allowed: Bool
        switch kind {
        case .go:
            allowed = ["go.dev", "golang.google.cn", "dl.google.com"].contains(host)
                && path.hasPrefix("/dl/go")
                && path.hasSuffix(".tar.gz")
                && path.contains(".darwin-")
        case .java:
            allowed = path.hasSuffix(".tar.gz") && (
                (host == "github.com" && path.hasPrefix("/adoptium/"))
                    || (host == "mirrors.tuna.tsinghua.edu.cn" && path.hasPrefix("/Adoptium/"))
            )
        case .rust:
            let archive = path.hasSuffix(".tar.gz") || path.hasSuffix(".tar.gz.sha256")
            allowed = archive && (
                (host == "static.rust-lang.org" && path.hasPrefix("/dist/rust-"))
                    || (host == "mirrors.ustc.edu.cn" && path.hasPrefix("/rust-static/dist/rust-"))
            )
        case .node, .python:
            allowed = false
        }
        return allowed ? raw : nil
    }
}

nonisolated enum OfficialCache {
    static func fileURL(
        kind: RuntimeKind,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appending(path: "Library/Application Support/MacBJ/catalog/\(kind.rawValue).tsv")
    }

    static func save(
        _ releases: [OfficialRelease],
        kind: RuntimeKind,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let lines = releases.compactMap { line($0, kind: kind) }
        let url = fileURL(kind: kind, home: home)
        let text = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
    }

    static func release(
        kind: RuntimeKind,
        version: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> OfficialRelease? {
        guard let text = try? String(contentsOf: fileURL(kind: kind, home: home), encoding: .utf8) else {
            return nil
        }
        let key = VersionOrder.key(version)
        return releases(in: text, kind: kind).first { VersionOrder.key($0.version) == key }
    }

    static func releases(in text: String, kind: RuntimeKind) -> [OfficialRelease] {
        text.lines.compactMap { row in
            let parts = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3,
                  let version = VersionToken.validated(parts[0]),
                  !version.contains(".."),
                  let url = OfficialURL.accepted(parts[2], kind: kind) else {
                return nil
            }
            let sha = parts[1].lowercased()
            if sha == "-", kind == .rust {
                return OfficialRelease(version: version, channel: .unknown, sha256: nil, url: url)
            }
            guard sha.wholeMatch(of: /^[0-9a-f]{64}$/) != nil else { return nil }
            return OfficialRelease(version: version, channel: .unknown, sha256: sha, url: url)
        }
    }

    private static func line(_ release: OfficialRelease, kind: RuntimeKind) -> String? {
        guard let version = VersionToken.validated(release.version),
              !version.contains(".."),
              version != "system",
              let url = OfficialURL.accepted(release.url, kind: kind) else {
            return nil
        }
        if let sha = release.sha256?.lowercased(), sha.wholeMatch(of: /^[0-9a-f]{64}$/) != nil {
            return "\(version)\t\(sha)\t\(url)"
        }
        guard kind == .rust else { return nil }
        return "\(version)\t-\t\(url)"
    }
}

nonisolated enum OfficialScripts {
    static func inspect(_ kind: RuntimeKind) -> String {
        guard kind.usesOfficialArchive, let tool = command(kind) else {
            return "printf '%s\\n' '__BACKEND__ none'\nexit 0\n"
        }
        let key = kind.rawValue
        return """
        setopt BARE_GLOB_QUAL NULL_GLOB
        root="$HOME/Library/Application Support/MacBJ/runtimes"
        printf '%s\\n' '__BACKEND__ official'
        printf '%s\\n' '__GLOBAL__'
        if [ -f "$root/global.tsv" ]; then
          awk -v k='\(key)' '$1 == k { print $2; exit }' "$root/global.tsv"
        fi
        printf '%s\\n' '__LIST__'
        if [ -d "$root/\(key)" ]; then
          for dir in "$root/\(key)"/*(N); do
            [ -d "$dir" ] || continue
            [ -x "$dir/\(tool.executable)" ] || continue
            basename "$dir"
          done
        fi
        printf '%s\\n' '__SYSTEM__'
        bin=$(command -v \(tool.name) 2>/dev/null || true)
        case "$bin" in
          "$root/\(key)/"*) ;;
          "") ;;
          *) \(tool.show) ;;
        esac
        exit 0
        """
    }

    static func install(kind: RuntimeKind, release: OfficialRelease) -> String? {
        guard let rooted = rooted(kind: kind, version: release.version),
              let tool = command(kind),
              let url = OfficialURL.accepted(release.url, kind: kind) else {
            return nil
        }
        let digest = release.sha256?.lowercased()
        if kind == .rust {
            guard digest == nil || digest?.wholeMatch(of: /^[0-9a-f]{64}$/) != nil else { return nil }
            guard OfficialURL.accepted(url + ".sha256", kind: kind) != nil else { return nil }
        } else {
            guard let digest, digest.wholeMatch(of: /^[0-9a-f]{64}$/) != nil else { return nil }
        }
        return rooted + """

        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        archive="$tmp/archive.tar.gz"
        \(download(url: url, sha256: kind == .rust ? nil : digest))
        \(extract(kind))
        test -x "$dest/\(tool.executable)"
        printf '%s\\n' \(ShellLiteral.singleQuoted(L("安装完成。")))
        """
    }

    static func uninstall(kind: RuntimeKind, version: String) -> String? {
        guard let rooted = rooted(kind: kind, version: version) else { return nil }
        let key = kind.rawValue
        return rooted + """

        if [ -d "$dest" ]; then
          rm -rf "$dest"
        fi
        file="$root/global.tsv"
        if [ -f "$file" ]; then
          tmp=$(mktemp)
          awk -v k='\(key)' -v v="$ver" '!($1 == k && $2 == v)' "$file" > "$tmp"
          mv "$tmp" "$file"
        fi
        printf '%s\\n' \(ShellLiteral.singleQuoted(L("已卸载。")))
        """
    }

    static func setGlobal(kind: RuntimeKind, version: String) -> String? {
        guard let rooted = rooted(kind: kind, version: version), let tool = command(kind) else { return nil }
        let key = kind.rawValue
        return rooted + """

        if [ ! -x "$dest/\(tool.executable)" ]; then
          printf '%s\\n' \(ShellLiteral.singleQuoted(L("先安装这个版本。"))) >&2
          exit 1
        fi
        file="$root/global.tsv"
        mkdir -p "$root"
        tmp=$(mktemp)
        if [ -f "$file" ]; then
          awk -v k='\(key)' '$1 != k' "$file" > "$tmp"
        else
          : > "$tmp"
        fi
        printf '%s\\t%s\\n' '\(key)' "$ver" >> "$tmp"
        mv "$tmp" "$file"
        printf '%s\\n' \(ShellLiteral.singleQuoted(L("已设为全局默认。")))
        """
    }

    private static func rooted(kind: RuntimeKind, version: String) -> String? {
        guard kind.usesOfficialArchive,
              version != "system",
              !version.contains(".."),
              let quoted = VersionToken.shellQuoted(version) else {
            return nil
        }
        let key = kind.rawValue
        return """
        set -eu
        root="$HOME/Library/Application Support/MacBJ/runtimes"
        ver=\(quoted)
        dest="$root/\(key)/$ver"
        case "$ver" in
          ""|*[!A-Za-z0-9._+-]*|*..*) printf '%s\\n' \(ShellLiteral.singleQuoted(L("版本号不能使用。"))) >&2; exit 1 ;;
        esac
        case "$dest" in
          "$root/\(key)/"*) ;;
          *) printf '%s\\n' \(ShellLiteral.singleQuoted(L("拒绝写入意外路径。"))) >&2; exit 1 ;;
        esac
        """
    }

    private static func download(url: String, sha256: String?) -> String {
        if let sha256 {
            return """
            printf '%s %s\\n' \(ShellLiteral.singleQuoted(L("正在下载"))) "$ver"
            curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 -o "$archive" '\(url)'
            printf '%s  %s\\n' '\(sha256)' "$archive" | shasum -a 256 -c -
            """
        }
        return """
        printf '%s %s\\n' \(ShellLiteral.singleQuoted(L("正在下载"))) "$ver"
        curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 -o "$archive" '\(url)'
        curl --proto '=https' --tlsv1.2 -fL --retry 3 --retry-delay 2 -o "$archive.sha256" '\(url).sha256'
        hash=$(awk 'NR==1 { print $1; exit }' "$archive.sha256")
        case "$hash" in
          *[!0-9a-fA-F]*) printf '%s\\n' \(ShellLiteral.singleQuoted(L("校验和无效。"))) >&2; exit 1 ;;
        esac
        [ "${#hash}" -eq 64 ] || exit 1
        printf '%s  %s\\n' "$hash" "$archive" | shasum -a 256 -c -
        """
    }

    private static func extract(_ kind: RuntimeKind) -> String {
        switch kind {
        case .go:
            return """
            tar -xzf "$archive" -C "$tmp"
            [ -d "$tmp/go" ]
            rm -rf "$dest"
            mkdir -p "${dest%/*}"
            mv "$tmp/go" "$dest"
            """
        case .java:
            return """
            tar -xzf "$archive" -C "$tmp"
            home=$(find "$tmp" -type d -path '*/Contents/Home' | head -n 1)
            [ -n "$home" ]
            jdk=$(dirname "$(dirname "$home")")
            rm -rf "$dest"
            mkdir -p "$dest"
            mv "$jdk/Contents" "$dest/Contents"
            """
        case .rust:
            return """
            tar -xzf "$archive" -C "$tmp"
            installer=$(find "$tmp" -name install.sh -maxdepth 3 | head -n 1)
            [ -n "$installer" ]
            rm -rf "$dest"
            mkdir -p "$dest"
            sh "$installer" --prefix="$dest" --without-modify-path
            """
        case .node, .python:
            return "exit 1"
        }
    }

    private struct Command {
        var name: String
        var executable: String
        var show: String
    }

    private static func command(_ kind: RuntimeKind) -> Command? {
        switch kind {
        case .go:
            Command(name: "go", executable: "bin/go", show: "go version 2>/dev/null || true")
        case .java:
            Command(name: "java", executable: "Contents/Home/bin/java", show: "java -version 2>&1 | head -n 1 || true")
        case .rust:
            Command(name: "rustc", executable: "bin/rustc", show: "rustc --version 2>/dev/null || true")
        case .node, .python:
            nil
        }
    }
}

nonisolated enum OfficialListing {
    static func versions(from output: String) -> [RuntimeVersion] {
        let lines = output.strippingTerminalFormatting().lines
        var section = ""
        var global = ""
        var names: [String] = []
        var hasSystem = false
        for line in lines {
            if line.hasPrefix("__BACKEND__") { continue }
            if line == "__GLOBAL__" || line.hasPrefix("__GLOBAL__ ") {
                section = "global"
                let inline = line.dropFirst("__GLOBAL__".count).trimmingCharacters(in: .whitespaces)
                if !inline.isEmpty, global.isEmpty { global = inline }
                continue
            }
            if line == "__LIST__" {
                section = "list"
                continue
            }
            if line == "__SYSTEM__" || line.hasPrefix("__SYSTEM__ ") {
                section = "system"
                let inline = line.dropFirst("__SYSTEM__".count).trimmingCharacters(in: .whitespaces)
                if !inline.isEmpty { hasSystem = true }
                continue
            }
            switch section {
            case "global":
                if global.isEmpty { global = line }
            case "list":
                guard let name = VersionToken.validated(line), name != "system", !names.contains(name) else { continue }
                names.append(name)
            case "system":
                if !line.isEmpty { hasSystem = true }
            default:
                break
            }
        }
        let current = VersionOrder.key(global)
        var versions = names.map { name in
            RuntimeVersion(name: name, isCurrent: !current.isEmpty && VersionOrder.key(name) == current)
        }
        if hasSystem {
            versions.append(RuntimeVersion(name: "system", isCurrent: false))
        }
        return versions
    }
}

nonisolated enum OfficialMirrors {
    static func applying(_ mirror: MirrorChoice, to release: OfficialRelease, kind: RuntimeKind) -> OfficialRelease {
        var copy = release
        let rewritten: String?
        switch kind {
        case .go:
            let arch = release.url.contains("darwin-amd64") ? "amd64" : "arm64"
            rewritten = GoIndex.url(version: release.version, arch: arch, mirror: mirror)
        case .java:
            let arch = release.url.contains("aarch64") ? "aarch64" : "x64"
            let feature = VersionOrder.major(release.version) ?? 0
            rewritten = JavaIndex.downloadURL(link: release.url, feature: feature, arch: arch, mirror: mirror)
        case .rust:
            let target = release.url.contains("x86_64-apple-darwin") ? "x86_64-apple-darwin" : "aarch64-apple-darwin"
            rewritten = RustIndex.url(version: release.version, target: target, mirror: mirror)
        case .node, .python:
            rewritten = nil
        }
        if let rewritten {
            copy.url = rewritten
        }
        return copy
    }
}

nonisolated struct OfficialProvider: RuntimeProvider {
    var kind: RuntimeKind

    func catalog(mirror: MirrorChoice) async -> RuntimeSnapshot {
        let kind = kind
        return await Task.detached(priority: .userInitiated) {
            guard kind.usesOfficialArchive else {
                return RuntimeSnapshot(kind: kind, backend: .missing, versions: [])
            }
            async let inspected = Shell.run(OfficialScripts.inspect(kind))
            async let fetched = OfficialIndex.fetch(kind, mirror: mirror)
            let output = await inspected
            let releases = await fetched
            if let releases {
                OfficialCache.save(releases, kind: kind)
            }
            let installed = OfficialListing.versions(from: output.stdout)
            let remote = (releases ?? []).map {
                RuntimeVersion(name: $0.version, isCurrent: false, isInstalled: false, channel: $0.channel)
            }
            let indexed = Dictionary(
                (releases ?? []).map { (VersionOrder.key($0.version), $0.channel) },
                uniquingKeysWith: { first, _ in first }
            )
            let versions = CatalogMerge.combining(installed: installed, remote: remote) { name in
                indexed[VersionOrder.key(name)] ?? .unknown
            }
            let loadError = (output.status != 0 && installed.isEmpty) ? ShellMessage.display(output.stderr) : nil
            return RuntimeSnapshot(
                kind: kind,
                backend: .official,
                versions: versions,
                loadError: loadError,
                remoteFailed: releases == nil
            )
        }.value
    }

    func installScript(backend: RuntimeBackend, version: String, mirror: MirrorChoice) -> String? {
        guard backend == .official, let cached = OfficialCache.release(kind: kind, version: version) else {
            return nil
        }
        return OfficialScripts.install(kind: kind, release: OfficialMirrors.applying(mirror, to: cached, kind: kind))
    }

    func uninstallScript(backend: RuntimeBackend, version: String) -> String? {
        guard backend == .official else { return nil }
        return OfficialScripts.uninstall(kind: kind, version: version)
    }

    func setGlobalScript(backend: RuntimeBackend, version: String) -> String? {
        guard backend == .official else { return nil }
        return OfficialScripts.setGlobal(kind: kind, version: version)
    }

    func projectPin(in directory: URL) -> ProjectPin? {
        ProjectPins.read(kind: kind, in: directory)
    }

    func writeProjectPin(_ version: String, in directory: URL) throws {
        try ProjectPins.write(kind: kind, version: version, in: directory)
    }

    func aliases(backend: RuntimeBackend) async -> [VersionAlias] {
        guard backend == .official else { return [] }
        return AliasTable.load(kind: kind, from: AliasTable.fileURL())
    }

    func setAlias(name: String, version: String, backend: RuntimeBackend) async throws {
        guard backend == .official else {
            throw RuntimeFailure(message: L("这个版本管理器不能保存别名。"))
        }
        try AliasTable.upsert(kind: kind, name: name, version: version, at: AliasTable.fileURL())
    }

    func removeAlias(name: String, backend: RuntimeBackend) async throws {
        guard backend == .official else {
            throw RuntimeFailure(message: L("这个版本管理器不能删除别名。"))
        }
        try AliasTable.remove(kind: kind, name: name, at: AliasTable.fileURL())
    }
}
