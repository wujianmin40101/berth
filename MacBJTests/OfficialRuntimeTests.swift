import Foundation
import Testing
@testable import MacBJ

struct OfficialRuntimeTests {
    @Test func `go index keeps stable darwin builds and marks the two newest minors`() throws {
        let data = try #require(goIndexJSON.data(using: .utf8))
        let releases = try #require(GoIndex.parse(data, arch: "arm64", mirror: .official))
        let channels = Dictionary(uniqueKeysWithValues: releases.map { ($0.version, $0.channel) })

        #expect(channels["1.27.1"] == .stable)
        #expect(channels["1.26.2"] == .stable)
        #expect(channels["1.25.0"] == .deprecated)
        #expect(channels["1.24.1"] == nil)
        #expect(channels["1.27.0-rc"] == nil)
        let newest = try #require(releases.first { $0.version == "1.27.1" })
        #expect(newest.url == "https://go.dev/dl/go1.27.1.darwin-arm64.tar.gz")
        #expect(newest.sha256 == String(repeating: "a", count: 64))
        #expect(GoIndex.url(version: "1.27.1", arch: "arm64", mirror: .china) == "https://golang.google.cn/dl/go1.27.1.darwin-arm64.tar.gz")
    }

    @Test func `java marks lts, the newest feature, and older features`() throws {
        let lts: Set<Int> = [8, 11, 17, 21, 25]
        #expect(JavaIndex.channel(feature: 25, lts: lts, newestFeature: 27) == .lts)
        #expect(JavaIndex.channel(feature: 27, lts: lts, newestFeature: 27) == .stable)
        #expect(JavaIndex.channel(feature: 26, lts: lts, newestFeature: 27) == .deprecated)

        let data = try #require(javaAssetJSON.data(using: .utf8))
        let stable = try #require(JavaIndex.release(
            feature: 27,
            data: data,
            lts: lts,
            newestFeature: 27,
            arch: "aarch64",
            mirror: .official
        ))
        #expect(stable.version == "27.0.1+1")
        #expect(stable.channel == .stable)
        #expect(stable.url.hasPrefix("https://github.com/adoptium/"))

        let mirrored = try #require(JavaIndex.release(
            feature: 27,
            data: data,
            lts: lts,
            newestFeature: 27,
            arch: "aarch64",
            mirror: .china
        ))
        #expect(mirrored.url == "https://mirrors.tuna.tsinghua.edu.cn/Adoptium/27/jdk/aarch64/mac/OpenJDK27U-jdk_aarch64_mac_hotspot_27.0.1_1.tar.gz")
        #expect(mirrored.sha256 == "c2619cb73ff1d296edd0644d92ae8ed94039bc1bdd43282398835b7f88134fb6")
    }

    @Test func `rust index keeps numbered releases and marks only the newest as stable`() throws {
        let data = try #require(rustReleasesJSON.data(using: .utf8))
        let releases = try #require(RustIndex.parse(data, mirror: .official, target: "aarch64-apple-darwin"))
        let channels = Dictionary(uniqueKeysWithValues: releases.map { ($0.version, $0.channel) })

        #expect(channels["1.99.1"] == .stable)
        #expect(channels["1.99.0"] == .deprecated)
        #expect(channels["beta"] == nil)
        #expect(channels["1.98.0-beta.1"] == nil)
        #expect(releases.first { $0.version == "1.99.1" }?.url == "https://static.rust-lang.org/dist/rust-1.99.1-aarch64-apple-darwin.tar.gz")
        #expect(RustIndex.url(version: "1.99.1", target: "aarch64-apple-darwin", mirror: .china) == "https://mirrors.ustc.edu.cn/rust-static/dist/rust-1.99.1-aarch64-apple-darwin.tar.gz")
    }

    @Test func `install scripts pin the official archive and reject shell injection`() {
        let sha = String(repeating: "a", count: 64)
        let go = OfficialRelease(
            version: "1.27.1",
            channel: .stable,
            sha256: sha,
            url: "https://go.dev/dl/go1.27.1.darwin-arm64.tar.gz"
        )
        let script = OfficialScripts.install(kind: .go, release: go)
        #expect(script?.contains("https://go.dev/dl/go1.27.1.darwin-arm64.tar.gz") == true)
        #expect(script?.contains(sha) == true)
        #expect(script?.contains("shasum -a 256 -c -") == true)
        #expect(script?.contains("$root/go/") == true)
        #expect(script?.contains(L("拒绝写入意外路径。")) == true)

        let java = OfficialScripts.install(kind: .java, release: OfficialRelease(
            version: "27.0.1+1",
            channel: .stable,
            sha256: sha,
            url: "https://github.com/adoptium/temurin27-binaries/releases/download/jdk-27.0.1%2B1/OpenJDK27U-jdk_aarch64_mac_hotspot_27.0.1_1.tar.gz"
        ))
        #expect(java?.contains("Contents/Home") == true)

        let rust = OfficialScripts.install(kind: .rust, release: OfficialRelease(
            version: "1.99.1",
            channel: .stable,
            sha256: nil,
            url: "https://static.rust-lang.org/dist/rust-1.99.1-aarch64-apple-darwin.tar.gz"
        ))
        #expect(rust?.contains("https://static.rust-lang.org/dist/rust-1.99.1-aarch64-apple-darwin.tar.gz.sha256") == true)
        #expect(rust?.contains("install.sh") == true)
        #expect(rust?.contains("--without-modify-path") == true)

        #expect(OfficialScripts.install(kind: .go, release: OfficialRelease(
            version: "1.27.1; rm -rf /",
            channel: .stable,
            sha256: sha,
            url: go.url
        )) == nil)
        #expect(OfficialScripts.install(kind: .go, release: OfficialRelease(
            version: "1.27.1",
            channel: .stable,
            sha256: sha,
            url: "https://evil.example/go1.27.1.darwin-arm64.tar.gz"
        )) == nil)
        #expect(OfficialScripts.install(kind: .go, release: OfficialRelease(
            version: "system",
            channel: .stable,
            sha256: sha,
            url: go.url
        )) == nil)
        #expect(OfficialScripts.setGlobal(kind: .go, version: "1.27.1")?.contains("global.tsv") == true)
        #expect(OfficialScripts.setGlobal(kind: .go, version: "1..2") == nil)
        #expect(OfficialScripts.uninstall(kind: .java, version: "27.0.1+1")?.contains("rm -rf") == true)
        #expect(OfficialScripts.uninstall(kind: .rust, version: "system") == nil)
    }

    @Test func `catalog cache keeps only allowlisted archives`() throws {
        let sha = String(repeating: "b", count: 64)
        let text = """
        1.27.1\t\(sha)\thttps://go.dev/dl/go1.27.1.darwin-arm64.tar.gz
        1.26.1\t\(sha)\thttps://evil.example/go.tar.gz
        1.26.2\tnot-a-sha\thttps://go.dev/dl/go1.26.2.darwin-arm64.tar.gz
        """
        let parsed = OfficialCache.releases(in: text, kind: .go)
        #expect(parsed.map(\.version) == ["1.27.1"])

        let home = FileManager.default.temporaryDirectory.appending(path: "macbj-catalog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        OfficialCache.save([
            OfficialRelease(version: "1.27.1", channel: .stable, sha256: sha, url: "https://go.dev/dl/go1.27.1.darwin-arm64.tar.gz"),
            OfficialRelease(version: "1.26.1", channel: .stable, sha256: sha, url: "https://evil.example/go.tar.gz")
        ], kind: .go, home: home)
        let loaded = OfficialCache.release(kind: .go, version: "1.27.1", home: home)
        #expect(loaded?.sha256 == sha)
        #expect(OfficialCache.release(kind: .go, version: "1.26.1", home: home) == nil)
    }

    @Test func `installed official versions keep the recorded global and a system row`() {
        let versions = OfficialListing.versions(from: """
        __BACKEND__ official
        __GLOBAL__
        1.27.1
        __LIST__
        1.27.1
        1.26.2
        __SYSTEM__
        go version go1.22.0 darwin/arm64
        """)
        #expect(versions.first { $0.name == "1.27.1" }?.isCurrent == true)
        #expect(versions.first { $0.name == "1.26.2" }?.isCurrent == false)
        #expect(versions.contains { $0.name == "system" && !$0.isCurrent })
    }

    @Test func `project pins write one official version file`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "macbj-pin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try ProjectPins.write(kind: .java, version: "11.0.32+101", in: root)
        let pin = ProjectPins.read(kind: .java, in: root)
        #expect(pin?.fileName == ".java-version")
        #expect(pin?.version == "11.0.32+101")
        #expect(pin?.writable == true)
        #expect(throws: RuntimeFailure.self) {
            try ProjectPins.write(kind: .go, version: "1.27.1; rm", in: root)
        }
        #expect(VersionOrder.isNewer("27.0.1+2", than: "27.0.1+1"))
        #expect(VersionOrder.isNewer("1.27.1", than: "1.26.10"))
    }

    @Test func `shell hook learns go java and rust without dropping node or python`() {
        let script = ShellHook.script
        #expect(script.contains(".go-version"))
        #expect(script.contains(".java-version"))
        #expect(script.contains(".rust-version"))
        #expect(script.contains("global.tsv"))
        #expect(script.contains("JAVA_HOME"))
        #expect(script.contains("nvm use \"$ver\""))
        #expect(script.contains("UV_PYTHON"))
        #expect(script.contains(".python-version"))
    }
}

private let goIndexJSON = """
[
  {"version":"go1.27.1","stable":true,"files":[
    {"filename":"go1.27.1.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","kind":"archive"}
  ]},
  {"version":"go1.26.2","stable":true,"files":[
    {"filename":"go1.26.2.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","kind":"archive"}
  ]},
  {"version":"go1.25.0","stable":true,"files":[
    {"filename":"go1.25.0.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","kind":"archive"}
  ]},
  {"version":"go1.27rc1","stable":false,"files":[
    {"filename":"go1.27rc1.darwin-arm64.tar.gz","os":"darwin","arch":"arm64","sha256":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd","kind":"archive"}
  ]},
  {"version":"go1.24.1","stable":true,"files":[
    {"filename":"go1.24.1.darwin-amd64.tar.gz","os":"darwin","arch":"amd64","sha256":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","kind":"archive"}
  ]}
]
"""

private let javaAssetJSON = """
[{
  "version_data": {"semver": "27.0.1+1"},
  "binaries": [{
    "package": {
      "link": "https://github.com/adoptium/temurin27-binaries/releases/download/jdk-27.0.1%2B1/OpenJDK27U-jdk_aarch64_mac_hotspot_27.0.1_1.tar.gz",
      "checksum": "c2619cb73ff1d296edd0644d92ae8ed94039bc1bdd43282398835b7f88134fb6"
    }
  }]
}]
"""

private let rustReleasesJSON = """
[
  {"tag_name":"1.99.1","prerelease":false,"draft":false},
  {"tag_name":"1.99.0","prerelease":false,"draft":false},
  {"tag_name":"beta","prerelease":true,"draft":false},
  {"tag_name":"1.98.0-beta.1","prerelease":false,"draft":false}
]
"""
