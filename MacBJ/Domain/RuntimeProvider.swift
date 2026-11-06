import Foundation

/// 一种运行时的版本管理。Node 和 Python 各有一个实现，之后的 Go / Java / Rust 也走这里。
nonisolated protocol RuntimeProvider: Sendable {
    var kind: RuntimeKind { get }

    func catalog(mirror: MirrorChoice) async -> RuntimeSnapshot

    func installScript(backend: RuntimeBackend, version: String, mirror: MirrorChoice) -> String?
    func uninstallScript(backend: RuntimeBackend, version: String) -> String?
    func setGlobalScript(backend: RuntimeBackend, version: String) -> String?

    func projectPin(in directory: URL) -> ProjectPin?
    func writeProjectPin(_ version: String, in directory: URL) throws

    func aliases(backend: RuntimeBackend) async -> [VersionAlias]
    func setAlias(name: String, version: String, backend: RuntimeBackend) async throws
    func removeAlias(name: String, backend: RuntimeBackend) async throws
}
