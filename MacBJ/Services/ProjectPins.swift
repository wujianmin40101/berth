import Foundation

nonisolated enum ProjectPins {
    static func read(kind: RuntimeKind, in directory: URL) -> ProjectPin? {
        switch kind {
        case .node:
            if let version = firstLine(in: directory, file: ".nvmrc") {
                return ProjectPin(fileName: ".nvmrc", version: version, writable: true)
            }
            if let version = firstLine(in: directory, file: ".node-version") {
                return ProjectPin(fileName: ".node-version", version: version, writable: true)
            }
            return nil
        case .python:
            if let version = firstLine(in: directory, file: ".python-version") {
                return ProjectPin(fileName: ".python-version", version: version, writable: true)
            }
            if let requirement = requiresPython(in: directory) {
                return ProjectPin(fileName: "pyproject.toml", version: requirement, writable: false)
            }
            return nil
        case .go, .java, .rust:
            guard let fileName = fileName(for: kind),
                  let version = firstLine(in: directory, file: fileName) else {
                return nil
            }
            return ProjectPin(fileName: fileName, version: version, writable: true)
        }
    }

    static func write(kind: RuntimeKind, version: String, in directory: URL) throws {
        guard let version = VersionToken.validated(version) else {
            throw RuntimeFailure(message: L("这个版本不能写入项目。"))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RuntimeFailure(message: L("项目目录不存在。"))
        }
        guard let fileName = fileName(for: kind) else {
            throw RuntimeFailure(message: L("这个版本不能写入项目。"))
        }
        let url = directory.appending(path: fileName)
        do {
            try (version + "\n").write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw RuntimeFailure(message: L("没有写入 %@。", fileName))
        }
    }

    static func fileName(for kind: RuntimeKind) -> String? {
        switch kind {
        case .node: ".nvmrc"
        case .python: ".python-version"
        case .go: ".go-version"
        case .java: ".java-version"
        case .rust: ".rust-version"
        }
    }

    static func requiresPython(in text: String) -> String? {
        guard let match = text.firstMatch(of: /requires-python\s*=\s*"([^"]+)"/) else { return nil }
        let value = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func firstLine(in directory: URL, file: String) -> String? {
        let url = directory.appending(path: file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = text.lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return line.isEmpty ? nil : line
    }

    private static func requiresPython(in directory: URL) -> String? {
        let url = directory.appending(path: "pyproject.toml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return requiresPython(in: text)
    }
}
