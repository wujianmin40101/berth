import Testing
@testable import MacBJ

struct ListingTests {
    @Test("nvm list uses the default alias as the active version")
    func nvmListUsesTheDefaultAliasAsTheActiveVersion() {
        let versions = NodeListing.versions(backend: .nvm, list: """
               v20.20.2 *
        ->     v22.23.4 *
                 system * (-> v25.8.1)
        default -> 22 (-> v22.23.4 *)
        iojs -> N/A (default)
        node -> stable (-> v22.23.4 *) (default)
        lts/iron -> v20.20.2 *
        lts/jod -> v22.23.4 *
        """)

        #expect(versions.map(\.name) == ["v20.20.2", "v22.23.4", "system"])
        #expect(versions.first(where: \.isCurrent)?.name == "v22.23.4")
    }

    @Test("nvm prefers default over the arrow when they differ")
    func nvmPrefersDefaultOverTheArrowWhenTheyDiffer() {
        let versions = NodeListing.versions(backend: .nvm, list: """
        ->     v20.20.2 *
               v22.23.4 *
        default -> 22 (-> v22.23.4 *)
        """)

        #expect(versions.first(where: \.isCurrent)?.name == "v22.23.4")
    }

    @Test("fnm list marks the default alias")
    func fnmListMarksTheDefaultAlias() {
        let versions = NodeListing.versions(backend: .fnm, list: """
        * v22.14.0 default
          v20.18.1
          system
        """)

        #expect(versions.map(\.title) == ["22.14.0", "20.18.1", "system"])
        #expect(versions.first(where: \.isCurrent)?.name == "v22.14.0")
    }

    @Test("volta list marks the default runtime")
    func voltaListMarksTheDefaultRuntime() {
        let versions = NodeListing.versions(backend: .volta, list: """
        runtime node@20.11.0
        runtime node@22.14.0 (default)
        """)

        #expect(versions.map(\.name) == ["20.11.0", "22.14.0"])
        #expect(versions.first(where: \.isCurrent)?.name == "22.14.0")
    }

    @Test("pyenv uses the global version when the star is local")
    func pyenvUsesTheGlobalVersionWhenTheStarIsLocal() {
        let versions = PythonListing.versions(
            backend: .pyenv,
            global: "3.11.9\n",
            list: """
            * 3.12.7 (set by /tmp/project/.python-version)
              3.11.9
              system
            """
        )

        #expect(versions.map(\.name) == ["3.12.7", "3.11.9", "system"])
        #expect(versions.first(where: \.isCurrent)?.name == "3.11.9")
    }

    @Test("uv list keeps one row per version and marks the resolved interpreter")
    func uvListKeepsOneRowPerVersionAndMarksTheResolvedInterpreter() {
        let versions = PythonListing.versions(
            backend: .uv,
            global: """
            /opt/homebrew/opt/python@3.14/bin/python3.14
            Python 3.14.3
            """,
            list: """
            cpython-3.14.3-macos-aarch64-none    /opt/homebrew/bin/python3.14 -> ../Cellar/python@3.14/3.14.3_1/bin/python3.14
            cpython-3.14.3-macos-aarch64-none    /opt/homebrew/bin/python3 -> ../Cellar/python@3.14/3.14.3_1/bin/python3
            cpython-3.9.6-macos-aarch64-none     /usr/bin/python3
            """
        )

        #expect(versions.map(\.name) == ["3.14.3", "3.9.6"])
        #expect(versions.first(where: \.isCurrent)?.name == "3.14.3")
    }

    @Test("probe text separates backend, global, and list")
    func probeTextSeparatesBackendGlobalAndList() {
        let probe = ProbeText.parse("""
        noise from the shell
        __BACKEND__ uv
        __GLOBAL__
        Python 3.14.3
        __LIST__
        cpython-3.14.3-macos-aarch64-none    /usr/bin/python3
        """)

        #expect(probe.backend == .uv)
        #expect(probe.global.contains("Python 3.14.3"))
        #expect(probe.list.contains("cpython-3.14.3"))
        #expect(!probe.list.contains("Python 3.14.3"))
    }

    @Test("version tokens reject shell syntax", arguments: ["22; rm -rf /", "3.12 && uname", "", "v22.14.0'"])
    func versionTokensRejectShellSyntax(raw: String) {
        #expect(VersionToken.validated(raw) == nil)
        #expect(RuntimeScripts.activate(.node, backend: .nvm, version: raw) == nil)
    }

    @Test("nvm activate command quotes the version")
    func nvmActivateCommandQuotesTheVersion() {
        let script = RuntimeScripts.activate(.node, backend: .nvm, version: "v22.23.4")
        #expect(script?.contains("nvm alias default 'v22.23.4'") == true)
    }
}
