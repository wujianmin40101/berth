import Foundation
import Testing
@testable import MacBJ

struct CatalogTests {
    @Test("node index marks current stable and the maintained lts lines")
    func nodeIndexMarksCurrentStableAndTheMaintainedLtsLines() throws {
        let data = try #require(nodeIndexJSON.data(using: .utf8))
        let releases = NodeIndex.parse(data)
        let offerings = NodeIndex.offerings(releases)

        #expect(channel("v25.2.0", releases) == .stable)
        #expect(channel("v24.11.0", releases) == .lts)
        #expect(channel("v24.10.0", releases) == .lts)
        #expect(channel("v22.23.4", releases) == .lts)
        #expect(channel("v22.22.0", releases) == .lts)
        #expect(channel("v20.20.2", releases) == .lts)
        #expect(channel("v18.20.8", releases) == .deprecated)
        #expect(offerings.map(\.version) == ["v25.2.0", "v24.11.0", "v22.23.4", "v20.20.2"])
        let krypton = releases.first { $0.version == "v24.11.0" }
        #expect(krypton?.releasedOn == "2026-01-01")
        #expect(krypton?.npm == "11.6.1")
        #expect(krypton?.v8 == "13.6.233.10")
        #expect(NodeIndex.displayDate("2026-10-21") == "Oct 21, 2026")
        #expect(NodeIndex.displayDate("2026-01-01") == "Jan 1, 2026")
        #expect(NodeIndex.displayDate(nil) == "—")
    }

    @Test("catalog keeps release metadata on an installed version")
    func catalogKeepsReleaseMetadataOnAnInstalledVersion() {
        let installed = [RuntimeVersion(name: "v22.23.4", isCurrent: true)]
        let remote = [
            RuntimeVersion(
                name: "v22.23.4",
                isCurrent: false,
                isInstalled: false,
                channel: .lts,
                releasedOn: "2026-01-01",
                npm: "10.9.2",
                v8: "12.4.254.21"
            ),
        ]
        let merged = CatalogMerge.combining(installed: installed, remote: remote) { _ in .unknown }
        let version = merged.first { $0.name == "v22.23.4" }
        #expect(merged.count == 1)
        #expect(version?.isInstalled == true)
        #expect(version?.isCurrent == true)
        #expect(version?.channel == .lts)
        #expect(version?.npm == "10.9.2")
        #expect(version?.v8 == "12.4.254.21")
        #expect(version?.releasedOn == "2026-01-01")
    }

    @Test("python remote list keeps the newest supported patch")
    func pythonRemoteListKeepsTheNewestSupportedPatch() {
        let offerings = PythonRemoteList.offerings(from: """
        Available versions:
          3.9.6
          3.10.16
          3.11.11
          3.12.7
          3.12.8
          3.14.0a1
          3.14.0
        cpython-3.13.1-macos-aarch64-none    <download available>
        cpython-3.13.1+freethreaded-macos-aarch64-none    <download available>
        """)

        #expect(offerings.map(\.name).sorted() == ["3.11.11", "3.12.8", "3.13.1", "3.14.0"])
        #expect(offerings.first { $0.name == "3.9.6" } == nil)
        #expect(offerings.first { $0.name == "3.12.8" }?.channel == .stable)
        #expect(PythonReleaseTable.channel(for: "3.9.6") == .deprecated)
    }

    @Test("project pins prefer nvmrc and keep pyproject read only")
    func projectPinsPreferNvmrcAndKeepPyprojectReadOnly() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "macbj-pins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "22.23.4\n".write(to: root.appending(path: ".nvmrc"), atomically: true, encoding: .utf8)
        try "20\n".write(to: root.appending(path: ".node-version"), atomically: true, encoding: .utf8)
        let node = ProjectPins.read(kind: .node, in: root)
        #expect(node?.fileName == ".nvmrc")
        #expect(node?.version == "22.23.4")
        #expect(node?.writable == true)

        try """
        [project]
        name = "demo"
        requires-python = ">=3.12"
        """.write(to: root.appending(path: "pyproject.toml"), atomically: true, encoding: .utf8)
        let requirement = ProjectPins.read(kind: .python, in: root)
        #expect(requirement?.fileName == "pyproject.toml")
        #expect(requirement?.version == ">=3.12")
        #expect(requirement?.writable == false)

        try ProjectPins.write(kind: .python, version: "3.12.8", in: root)
        let written = ProjectPins.read(kind: .python, in: root)
        #expect(written?.fileName == ".python-version")
        #expect(written?.version == "3.12.8")
        let toml = try String(contentsOf: root.appending(path: "pyproject.toml"), encoding: .utf8)
        #expect(toml.contains("requires-python = \">=3.12\""))
    }

    @Test("alias names reject reserved words and shell syntax")
    func aliasNamesRejectReservedWordsAndShellSyntax() throws {
        #expect(AliasName.validated("default") == nil)
        #expect(AliasName.validated("my-default") == "my-default")
        #expect(throws: RuntimeFailure.self) {
            try AliasTable.upsert(kind: .node, name: "22; rm", version: "v22.23.4", in: "")
        }

        let updated = try AliasTable.upsert(kind: .python, name: "my-default", version: "3.12.8", in: "node team v22.23.4\n")
        let records = AliasTable.records(from: updated)
        #expect(records.contains(AliasRecord(kind: .python, name: "my-default", version: "3.12.8")))
        #expect(records.contains(AliasRecord(kind: .node, name: "team", version: "v22.23.4")))

        let aliases = AliasListing.parseArrowList("""
        default -> 22 (-> v22.23.4 *)
        my-default -> 20 (-> v20.20.2 *)
        lts/jod -> v22.23.4 *
        node -> stable (-> v22.23.4 *) (default)
        """)
        #expect(aliases == [VersionAlias(name: "my-default", version: "v20.20.2")])
    }

    @Test("nvm install command quotes the version and can point at the china mirror")
    func nvmInstallCommandQuotesTheVersionAndCanPointAtTheChinaMirror() {
        let script = NodeProvider().installScript(backend: .nvm, version: "v22.23.4", mirror: .china)
        #expect(script?.contains("export NVM_NODEJS_ORG_MIRROR='https://npmmirror.com/mirrors/node'") == true)
        #expect(script?.contains("nvm install 'v22.23.4'") == true)
        #expect(NodeProvider().installScript(backend: .nvm, version: "22; rm -rf /", mirror: .official) == nil)
        let alias = NodeProvider.aliasScript(backend: .nvm, name: "my-default", version: "v22.23.4")
        #expect(alias?.contains("nvm alias 'my-default' 'v22.23.4'") == true)
        #expect(NodeProvider.aliasScript(backend: .nvm, name: "default", version: "v22.23.4") == nil)
    }

    @Test("shell hook replaces its own block and leaves the rest of zshrc")
    func shellHookReplacesItsOwnBlockAndLeavesTheRestOfZshrc() throws {
        let original = "export FOO=1\n"
        let once = ShellHook.installing(into: original)
        let twice = ShellHook.installing(into: once)

        #expect(once.contains("export FOO=1"))
        #expect(once.contains("add-zsh-hook chpwd macbj_chpwd"))
        #expect(once.contains("nvm use \"$ver\""))
        #expect(once.contains(".python-version"))
        #expect(once.contains("UV_PYTHON"))
        #expect(once.contains("aliases.tsv"))
        #expect(ShellHook.status(of: original) == .missing)
        #expect(ShellHook.status(of: once) == .installed)
        #expect(twice.components(separatedBy: ShellHook.begin).count == 2)

        let root = FileManager.default.temporaryDirectory.appending(path: "macbj-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let zshrc = root.appending(path: ".zshrc")
        try original.write(to: zshrc, atomically: true, encoding: .utf8)
        try ShellHook.apply(to: zshrc)
        let backup = root.appending(path: ".zshrc.macbj-bak")
        #expect(try String(contentsOf: backup, encoding: .utf8) == original)
        #expect(ShellHook.status(of: try String(contentsOf: zshrc, encoding: .utf8)) == .installed)
    }

    private func channel(_ version: String, _ releases: [NodeRelease]) -> ReleaseChannel {
        NodeIndex.channel(of: version, in: releases)
    }
}

private let nodeIndexJSON = """
[
  {"version":"v25.2.0","lts":false,"date":"2026-02-01"},
  {"version":"v24.11.0","lts":"Krypton","date":"2026-01-01","npm":"11.6.1","v8":"13.6.233.10"},
  {"version":"v24.10.0","lts":false,"date":"2025-11-01"},
  {"version":"v22.23.4","lts":"Jod","date":"2026-01-01"},
  {"version":"v22.22.0","lts":"Jod","date":"2025-12-01"},
  {"version":"v20.20.2","lts":"Iron","date":"2025-01-01"},
  {"version":"v18.20.8","lts":"Hydrogen","date":"2024-01-01"},
  {"version":"v25.0.0-rc.1","lts":false,"date":"2025-12-01"}
]
"""
