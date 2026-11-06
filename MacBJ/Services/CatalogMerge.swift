import Foundation

nonisolated enum CatalogMerge {
    static func combining(
        installed: [RuntimeVersion],
        remote: [RuntimeVersion],
        channel: (String) -> ReleaseChannel
    ) -> [RuntimeVersion] {
        let remoteByKey = Dictionary(
            remote.map { (VersionOrder.key($0.name), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let installedVersions = installed.map { version in
            var copy = version
            copy.isInstalled = true
            guard version.name != "system" else { return copy }
            if let match = remoteByKey[VersionOrder.key(version.name)] {
                if match.channel != .unknown {
                    copy.channel = match.channel
                }
                copy.releasedOn = match.releasedOn
                copy.npm = match.npm
                copy.v8 = match.v8
            } else {
                let resolved = channel(version.name)
                if resolved != .unknown {
                    copy.channel = resolved
                }
            }
            return copy
        }
        let installedKeys = Set(installedVersions.map { VersionOrder.key($0.name) })
        let downloads = ranked(
            remote.filter { !$0.isInstalled && !installedKeys.contains(VersionOrder.key($0.name)) }
        )
        let sortedInstalled = ranked(installedVersions) { lhs, rhs in
            if lhs.name == "system" { return false }
            if rhs.name == "system" { return true }
            return VersionOrder.isNewer(lhs.parts, than: rhs.parts)
        }
        return sortedInstalled + downloads
    }

    private static func ranked(_ versions: [RuntimeVersion]) -> [RuntimeVersion] {
        ranked(versions) { VersionOrder.isNewer($0.parts, than: $1.parts) }
    }

    private static func ranked(
        _ versions: [RuntimeVersion],
        by comesFirst: (Ranked, Ranked) -> Bool
    ) -> [RuntimeVersion] {
        versions
            .map { Ranked(version: $0, parts: VersionOrder.parts($0.name)) }
            .sorted(by: comesFirst)
            .map(\.version)
    }

    private nonisolated struct Ranked {
        var version: RuntimeVersion
        var parts: [Int]
        var name: String { version.name }
    }
}
