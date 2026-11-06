import Foundation

nonisolated enum NodeListing {
    static func versions(backend: RuntimeBackend, list: String) -> [RuntimeVersion] {
        let text = list.strippingTerminalFormatting()
        switch backend {
        case .fnm:
            return parseFnm(text)
        case .nvm:
            return parseNvm(text)
        case .volta:
            return parseVolta(text)
        case .missing:
            return parseBare(text)
        case .pyenv, .uv, .official:
            return []
        }
    }

    private static func parseNvm(_ text: String) -> [RuntimeVersion] {
        var versions: [RuntimeVersion] = []
        var defaultName: String?
        var arrowName: String?

        for line in text.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("default ->") {
                defaultName = firstNodeVersion(in: trimmed) ?? (trimmed.contains("system") ? "system" : nil)
                continue
            }
            if let match = line.wholeMatch(of: /^\s*(->)?\s*(v\d+\.\d+\.\d+)\s*\*?\s*$/) {
                let name = String(match.2)
                if match.1 != nil {
                    arrowName = name
                }
                append(RuntimeVersion(name: name, isCurrent: false), to: &versions)
                continue
            }
            let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
            if tokens.first == "system" {
                append(RuntimeVersion(name: "system", isCurrent: false), to: &versions)
            }
        }

        markCurrent(defaultName ?? arrowName, in: &versions)
        return versions
    }

    private static func parseFnm(_ text: String) -> [RuntimeVersion] {
        var versions: [RuntimeVersion] = []
        var defaultName: String?
        var starredName: String?

        for line in text.lines {
            guard let match = line.wholeMatch(of: /^\s*(\*)?\s*(v\d+\.\d+\.\d+|system)(?:\s+(.*))?$/) else {
                continue
            }
            let name = String(match.2)
            let aliases = match.3.map { String($0) } ?? ""
            if match.1 != nil {
                starredName = name
            }
            if aliases.split(whereSeparator: \.isWhitespace).contains(where: { $0 == "default" }) {
                defaultName = name
            }
            append(RuntimeVersion(name: name, isCurrent: false), to: &versions)
        }

        markCurrent(defaultName ?? starredName, in: &versions)
        return versions
    }

    private static func parseVolta(_ text: String) -> [RuntimeVersion] {
        var versions: [RuntimeVersion] = []
        var defaultName: String?

        for line in text.lines {
            guard let match = line.firstMatch(of: /node@(\d+\.\d+\.\d+)/) else { continue }
            let name = String(match.1)
            if line.contains("(default)") {
                defaultName = name
            }
            append(RuntimeVersion(name: name, isCurrent: false), to: &versions)
        }

        markCurrent(defaultName, in: &versions)
        return versions
    }

    private static func parseBare(_ text: String) -> [RuntimeVersion] {
        guard let name = firstNodeVersion(in: text) else { return [] }
        return [RuntimeVersion(name: name, isCurrent: true)]
    }

    private static func firstNodeVersion(in text: String) -> String? {
        guard let match = text.firstMatch(of: /v\d+\.\d+\.\d+/) else { return nil }
        return String(match.0)
    }
}

nonisolated func append(_ version: RuntimeVersion, to versions: inout [RuntimeVersion]) {
    guard !versions.contains(where: { $0.name == version.name }) else { return }
    versions.append(version)
}

nonisolated func markCurrent(_ name: String?, in versions: inout [RuntimeVersion]) {
    guard let name else { return }
    for index in versions.indices {
        versions[index].isCurrent = versions[index].name == name
    }
}

nonisolated extension String {
    var lines: [String] {
        split(whereSeparator: \.isNewline).map(String.init)
    }

    func strippingTerminalFormatting() -> String {
        replacing(/\u{1B}\[[0-9;]*[A-Za-z]/, with: "")
    }
}
