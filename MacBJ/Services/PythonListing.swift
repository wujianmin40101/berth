import Foundation

nonisolated enum PythonListing {
    static func versions(backend: RuntimeBackend, global: String, list: String) -> [RuntimeVersion] {
        switch backend {
        case .pyenv:
            return parsePyenv(global: global, list: list)
        case .uv:
            return parseUv(global: global, list: list)
        case .missing:
            return parseBare(global.isEmpty ? list : global)
        case .fnm, .nvm, .volta, .official:
            return []
        }
    }

    private static func parsePyenv(global: String, list: String) -> [RuntimeVersion] {
        var versions: [RuntimeVersion] = []
        for line in list.lines {
            guard let match = line.wholeMatch(of: /^\s*\*?\s*([A-Za-z0-9][A-Za-z0-9._+-]*).*$/) else {
                continue
            }
            let name = String(match.1)
            guard name != "->" else { continue }
            append(RuntimeVersion(name: name, isCurrent: false), to: &versions)
        }
        let current = global.lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        applyCurrent(current, to: &versions)
        return versions
    }

    private static func parseUv(global: String, list: String) -> [RuntimeVersion] {
        var versions: [RuntimeVersion] = []
        for line in list.lines {
            guard let match = line.firstMatch(of: /cpython-(\d+\.\d+(?:\.\d+)?)-/) else { continue }
            append(RuntimeVersion(name: String(match.1), isCurrent: false), to: &versions)
        }
        let current = pythonVersion(in: global)
        applyCurrent(current, to: &versions)
        return versions
    }

    private static func parseBare(_ text: String) -> [RuntimeVersion] {
        guard let name = pythonVersion(in: text) else { return [] }
        return [RuntimeVersion(name: name, isCurrent: true)]
    }

    private static func pythonVersion(in text: String) -> String? {
        guard let match = text.firstMatch(of: /Python (\d+\.\d+(?:\.\d+)?)/) else { return nil }
        return String(match.1)
    }

    private static func applyCurrent(_ name: String?, to versions: inout [RuntimeVersion]) {
        guard let name, !name.isEmpty else { return }
        if !versions.contains(where: { $0.name == name }) {
            versions.insert(RuntimeVersion(name: name, isCurrent: false), at: 0)
        }
        markCurrent(name, in: &versions)
    }
}
