import Foundation

nonisolated enum PythonReleaseTable {
    /// 2026-11 时仍在收安全更新的版本标为稳定，已经停止维护的标为已弃用。
    private static let byMinor: [String: ReleaseChannel] = [
        "3.14": .stable,
        "3.13": .stable,
        "3.12": .stable,
        "3.11": .stable,
        "3.10": .deprecated,
        "3.9": .deprecated,
        "3.8": .deprecated,
        "3.7": .deprecated,
    ]

    static func channel(for version: String) -> ReleaseChannel {
        guard let minor = VersionOrder.minorKey(version) else { return .unknown }
        return byMinor[minor] ?? .unknown
    }
}

nonisolated enum PythonRemoteList {
    static func offerings(from text: String) -> [RuntimeVersion] {
        var best: [String: String] = [:]
        for name in candidates(from: text) {
            let channel = PythonReleaseTable.channel(for: name)
            guard channel != .deprecated, let minor = VersionOrder.minorKey(name) else { continue }
            if let existing = best[minor], !VersionOrder.isNewer(name, than: existing) {
                continue
            }
            best[minor] = name
        }
        return best.values.map { name in
            RuntimeVersion(
                name: name,
                isCurrent: false,
                isInstalled: false,
                channel: PythonReleaseTable.channel(for: name)
            )
        }
    }

    private static func candidates(from text: String) -> [String] {
        var names: [String] = []
        for line in text.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("freethreaded") || trimmed.contains("pypy") || trimmed.contains("graalpy") {
                continue
            }
            if let match = trimmed.wholeMatch(of: /^(\d+\.\d+\.\d+)$/) {
                append(String(match.1), to: &names)
                continue
            }
            if let match = trimmed.firstMatch(of: /^cpython-(\d+\.\d+\.\d+)-/) {
                append(String(match.1), to: &names)
            }
        }
        return names
    }

    private static func append(_ name: String, to names: inout [String]) {
        guard !names.contains(name) else { return }
        names.append(name)
    }
}
