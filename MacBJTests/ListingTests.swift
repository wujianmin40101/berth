import Testing
@testable import MacBJ

struct ListingTests {
    @Test func `nvm list uses the default alias as the active version`() {
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

    @Test func `nvm prefers default over the arrow when they differ`() {
        let versions = NodeListing.versions(backend: .nvm, list: """
        ->     v20.20.2 *
               v22.23.4 *
        default -> 22 (-> v22.23.4 *)
        """)

        #expect(versions.first(where: \.isCurrent)?.name == "v22.23.4")
    }

    @Test func `fnm list marks the default alias`() {
        let versions = NodeListing.versions(backend: .fnm, list: """
        * v22.14.0 default
          v20.18.1
          system
        """)

        #expect(versions.map(\.title) == ["22.14.0", "20.18.1", "system"])
        #expect(versions.first(where: \.isCurrent)?.name == "v22.14.0")
    }

    @Test func `volta list marks the default runtime`() {
        let versions = NodeListing.versions(backend: .volta, list: """
        runtime node@20.11.0
        runtime node@22.14.0 (default)
        """)

        #expect(versions.map(\.name) == ["20.11.0", "22.14.0"])
        #expect(versions.first(where: \.isCurrent)?.name == "22.14.0")
    }

    @Test func `pyenv uses the global version when the star is local`() {
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

    @Test func `uv list keeps one row per version and marks the resolved interpreter`() {
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

    @Test func `probe text separates backend, global, and list`() {
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

    @Test(arguments: ["22; rm -rf /", "3.12 && uname", "", "v22.14.0'"])
    func `version tokens reject shell syntax`(raw: String) {
        #expect(VersionToken.validated(raw) == nil)
        #expect(RuntimeScripts.activate(.node, backend: .nvm, version: raw) == nil)
    }

    @Test func `nvm activate command quotes the version`() {
        let script = RuntimeScripts.activate(.node, backend: .nvm, version: "v22.23.4")
        #expect(script?.contains("nvm alias default 'v22.23.4'") == true)
    }
}
