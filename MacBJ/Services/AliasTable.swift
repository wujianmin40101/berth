import Foundation

nonisolated struct AliasRecord: Equatable, Sendable {
    var kind: RuntimeKind
    var name: String
    var version: String
}

nonisolated enum AliasName {
    static let reserved: Set<String> = ["default", "node", "stable", "unstable", "iojs", "system"]

    static func validated(_ raw: String) -> String? {
        guard let name = VersionToken.validated(raw), !reserved.contains(name) else { return nil }
        return name
    }
}

nonisolated enum AliasTable {
    static func fileURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: "Library/Application Support/MacBJ/aliases.tsv")
    }

    static func records(from text: String) -> [AliasRecord] {
        text.lines.compactMap { line in
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == 3,
                  let kind = RuntimeKind(rawValue: parts[0]),
                  AliasName.validated(parts[1]) != nil,
                  VersionToken.validated(parts[2]) != nil
            else { return nil }
            return AliasRecord(kind: kind, name: parts[1], version: parts[2])
        }
    }

    static func text(from records: [AliasRecord]) -> String {
        records
            .map { "\($0.kind.rawValue) \($0.name) \($0.version)" }
            .joined(separator: "\n")
            .appending(records.isEmpty ? "" : "\n")
    }

    static func upsert(kind: RuntimeKind, name: String, version: String, in text: String) throws -> String {
        guard let name = AliasName.validated(name), let version = VersionToken.validated(version) else {
            throw RuntimeFailure(message: L("别名或版本号不能使用。default 请用「设为全局默认」。"))
        }
        var records = records(from: text).filter { !($0.kind == kind && $0.name == name) }
        records.append(AliasRecord(kind: kind, name: name, version: version))
        records.sort { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.name < rhs.name
        }
        return Self.text(from: records)
    }

    static func remove(kind: RuntimeKind, name: String, from text: String) -> String {
        let records = records(from: text).filter { !($0.kind == kind && $0.name == name) }
        return Self.text(from: records)
    }

    static func load(kind: RuntimeKind, from url: URL) -> [VersionAlias] {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        return records(from: text)
            .filter { $0.kind == kind }
            .map { VersionAlias(name: $0.name, version: $0.version) }
    }

    static func upsert(kind: RuntimeKind, name: String, version: String, at url: URL) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = try upsert(kind: kind, name: name, version: version, in: existing)
        try write(updated, to: url)
    }

    static func remove(kind: RuntimeKind, name: String, at url: URL) throws {
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try write(remove(kind: kind, name: name, from: existing), to: url)
    }

    private static func write(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch let failure as RuntimeFailure {
            throw failure
        } catch {
            throw RuntimeFailure(message: L("没有保存别名。"))
        }
    }
}

nonisolated enum AliasListing {
    static func parseArrowList(_ text: String) -> [VersionAlias] {
        var aliases: [VersionAlias] = []
        for line in text.strippingTerminalFormatting().lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let match = trimmed.firstMatch(of: /^([A-Za-z0-9][A-Za-z0-9._+-]*)\s+->\s+(\S+)/) else {
                continue
            }
            let name = String(match.1)
            guard AliasName.validated(name) != nil else { continue }
            let version = resolvedVersion(in: trimmed) ?? String(match.2)
            guard VersionToken.validated(version) != nil else { continue }
            if let index = aliases.firstIndex(where: { $0.name == name }) {
                aliases[index] = VersionAlias(name: name, version: version)
            } else {
                aliases.append(VersionAlias(name: name, version: version))
            }
        }
        return aliases
    }

    private static func resolvedVersion(in line: String) -> String? {
        guard let match = line.firstMatch(of: /->\s*(v\d+\.\d+\.\d+)/) else { return nil }
        return String(match.1)
    }
}
