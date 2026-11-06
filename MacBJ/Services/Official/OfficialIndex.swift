import Foundation

nonisolated enum OfficialHost {
    static var goArch: String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }

    static var javaArch: String {
        #if arch(arm64)
        "aarch64"
        #else
        "x64"
        #endif
    }

    static var rustTarget: String {
        #if arch(arm64)
        "aarch64-apple-darwin"
        #else
        "x86_64-apple-darwin"
        #endif
    }
}

nonisolated enum OfficialIndex {
    static func fetch(_ kind: RuntimeKind, mirror: MirrorChoice) async -> [OfficialRelease]? {
        switch kind {
        case .go: await GoIndex.fetch(mirror)
        case .java: await JavaIndex.fetch(mirror)
        case .rust: await RustIndex.fetch(mirror)
        case .node, .python: nil
        }
    }
}

private nonisolated enum OfficialBody {
    case data(Data)
    case missing
    case failed
}

private nonisolated enum OfficialHTTP {
    static func get(_ address: String) async -> OfficialBody {
        guard let url = URL(string: address) else { return .failed }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("MacBJ", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failed }
            if http.statusCode == 404 { return .missing }
            guard (200..<300).contains(http.statusCode) else { return .failed }
            return .data(data)
        } catch {
            return .failed
        }
    }
}

nonisolated enum GoIndex {
    static func fetch(_ mirror: MirrorChoice) async -> [OfficialRelease]? {
        let address = mirror == .china
            ? "https://golang.google.cn/dl/?mode=json&include=all"
            : "https://go.dev/dl/?mode=json&include=all"
        guard case .data(let data) = await OfficialHTTP.get(address) else { return nil }
        return parse(data, arch: OfficialHost.goArch, mirror: mirror)
    }

    static func parse(_ data: Data, arch: String, mirror: MirrorChoice) -> [OfficialRelease]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        var chosen: [String: OfficialRelease] = [:]
        for row in rows where row.stable {
            guard row.version.wholeMatch(of: /^go\d+\.\d+\.\d+$/) != nil else { continue }
            let version = String(row.version.dropFirst(2))
            guard let file = row.files.first(where: { item in
                item.os == "darwin"
                    && item.arch == arch
                    && (item.kind == nil || item.kind == "archive")
                    && item.filename == "go\(version).darwin-\(arch).tar.gz"
            }),
            let sha = file.sha256?.lowercased(),
            sha.wholeMatch(of: /^[0-9a-f]{64}$/) != nil,
            let url = url(version: version, arch: arch, mirror: mirror) else {
                continue
            }
            if chosen[version] == nil {
                chosen[version] = OfficialRelease(version: version, channel: .unknown, sha256: sha, url: url)
            }
        }
        let minors = Set(chosen.values.compactMap { VersionOrder.minorKey($0.version) })
        let supported = Set(minors.sorted { VersionOrder.isNewer($0, than: $1) }.prefix(2))
        return chosen.values.map { release in
            var copy = release
            let minor = VersionOrder.minorKey(release.version)
            copy.channel = minor.map { supported.contains($0) } == true ? .stable : .deprecated
            return copy
        }
    }

    static func url(version: String, arch: String, mirror: MirrorChoice) -> String? {
        guard VersionToken.validated(version) != nil, arch == "arm64" || arch == "amd64" else { return nil }
        let host = mirror == .china ? "https://golang.google.cn/dl" : "https://go.dev/dl"
        return OfficialURL.accepted("\(host)/go\(version).darwin-\(arch).tar.gz", kind: .go)
    }

    private struct Row: Decodable {
        var version: String
        var stable: Bool
        var files: [File]

        enum CodingKeys: String, CodingKey {
            case version, stable, files
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            version = try container.decode(String.self, forKey: .version)
            stable = try container.decodeIfPresent(Bool.self, forKey: .stable) ?? false
            files = try container.decodeIfPresent([File].self, forKey: .files) ?? []
        }
    }

    private struct File: Decodable {
        var filename: String
        var os: String
        var arch: String
        var sha256: String?
        var kind: String?
    }
}

nonisolated enum JavaIndex {
    static func fetch(_ mirror: MirrorChoice) async -> [OfficialRelease]? {
        guard case .data(let data) = await OfficialHTTP.get("https://api.adoptium.net/v3/info/available_releases"),
              let info = try? JSONDecoder().decode(Policy.self, from: data) else {
            return nil
        }
        let lts = Set(info.lts)
        let arch = OfficialHost.javaArch
        return await withTaskGroup(of: AssetOutcome.self) { group in
            for feature in info.available {
                group.addTask {
                    await asset(
                        feature: feature,
                        arch: arch,
                        mirror: mirror,
                        lts: lts,
                        newestFeature: info.newest
                    )
                }
            }
            var releases: [OfficialRelease] = []
            var failures = 0
            var finished = 0
            for await outcome in group {
                finished += 1
                switch outcome {
                case .release(let release):
                    releases.append(release)
                case .empty:
                    break
                case .failed:
                    failures += 1
                }
            }
            if !info.available.isEmpty, failures == finished { return nil }
            return releases
        }
    }

    static func channel(feature: Int, lts: Set<Int>, newestFeature: Int) -> ReleaseChannel {
        if lts.contains(feature) { return .lts }
        if feature == newestFeature { return .stable }
        return .deprecated
    }

    static func release(
        feature: Int,
        data: Data,
        lts: Set<Int>,
        newestFeature: Int,
        arch: String,
        mirror: MirrorChoice
    ) -> OfficialRelease? {
        guard let pages = try? JSONDecoder().decode([AssetPage].self, from: data),
              let page = pages.first,
              let package = page.binaries.first?.bundle,
              let version = VersionToken.validated(page.versionData.semver),
              !version.contains(".."),
              let sha = package.checksum?.lowercased(),
              sha.wholeMatch(of: /^[0-9a-f]{64}$/) != nil,
              let url = downloadURL(link: package.link, feature: feature, arch: arch, mirror: mirror) else {
            return nil
        }
        return OfficialRelease(
            version: version,
            channel: channel(feature: feature, lts: lts, newestFeature: newestFeature),
            sha256: sha,
            url: url
        )
    }

    static func downloadURL(link: String, feature: Int, arch: String, mirror: MirrorChoice) -> String? {
        guard let official = OfficialURL.accepted(link, kind: .java) else { return nil }
        guard mirror == .china,
              let name = URL(string: link)?.lastPathComponent.removingPercentEncoding,
              !name.isEmpty,
              !name.contains("'") else {
            return official
        }
        let china = "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/\(feature)/jdk/\(arch)/mac/\(name)"
        return OfficialURL.accepted(china, kind: .java) ?? official
    }

    private static func asset(
        feature: Int,
        arch: String,
        mirror: MirrorChoice,
        lts: Set<Int>,
        newestFeature: Int
    ) async -> AssetOutcome {
        let address = "https://api.adoptium.net/v3/assets/feature_releases/\(feature)/ga?architecture=\(arch)&image_type=jdk&os=mac&vendor=eclipse&page_size=1&sort_method=DATE&sort_order=DESC"
        switch await OfficialHTTP.get(address) {
        case .failed:
            return .failed
        case .missing:
            return .empty
        case .data(let data):
            guard let release = release(
                feature: feature,
                data: data,
                lts: lts,
                newestFeature: newestFeature,
                arch: arch,
                mirror: mirror
            ) else {
                return .empty
            }
            return .release(release)
        }
    }

    private enum AssetOutcome: Sendable {
        case release(OfficialRelease)
        case empty
        case failed
    }

    private struct Policy: Decodable {
        var lts: [Int]
        var available: [Int]
        var newest: Int

        enum CodingKeys: String, CodingKey {
            case lts = "available_lts_releases"
            case available = "available_releases"
            case newest = "most_recent_feature_release"
        }
    }

    private struct AssetPage: Decodable {
        var binaries: [Binary]
        var versionData: Version

        enum CodingKeys: String, CodingKey {
            case binaries
            case versionData = "version_data"
        }
    }

    private struct Version: Decodable {
        var semver: String
    }

    private struct Binary: Decodable {
        var bundle: Package

        enum CodingKeys: String, CodingKey {
            case bundle = "package"
        }
    }

    private struct Package: Decodable {
        var link: String
        var checksum: String?
    }
}

nonisolated enum RustIndex {
    static func fetch(_ mirror: MirrorChoice) async -> [OfficialRelease]? {
        guard case .data(let data) = await OfficialHTTP.get("https://api.github.com/repos/rust-lang/rust/releases?per_page=100") else {
            return nil
        }
        return parse(data, mirror: mirror, target: OfficialHost.rustTarget)
    }

    static func parse(_ data: Data, mirror: MirrorChoice, target: String) -> [OfficialRelease]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        var names: [String] = []
        for row in rows where !row.draft && !row.prerelease {
            guard row.tagName.wholeMatch(of: /^\d+\.\d+\.\d+$/) != nil, !names.contains(row.tagName) else { continue }
            names.append(row.tagName)
        }
        guard let newest = names.max(by: { VersionOrder.isNewer($1, than: $0) }) else { return [] }
        return names.compactMap { name in
            guard let url = url(version: name, target: target, mirror: mirror) else { return nil }
            return OfficialRelease(
                version: name,
                channel: name == newest ? .stable : .deprecated,
                sha256: nil,
                url: url
            )
        }
    }

    static func url(version: String, target: String, mirror: MirrorChoice) -> String? {
        guard VersionToken.validated(version) != nil,
              target == "aarch64-apple-darwin" || target == "x86_64-apple-darwin" else {
            return nil
        }
        let host = mirror == .china
            ? "https://mirrors.ustc.edu.cn/rust-static/dist"
            : "https://static.rust-lang.org/dist"
        return OfficialURL.accepted("\(host)/rust-\(version)-\(target).tar.gz", kind: .rust)
    }

    private struct Row: Decodable {
        var tagName: String
        var prerelease: Bool
        var draft: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case prerelease
            case draft
        }
    }
}
