import Foundation
import Testing
@testable import MacBJ

struct ToolboxTests {
    @Test func `lsof field output becomes port rows`() {
        let text = """
        p431
        cnode
        n*:3000
        p88
        cpython3.14
        n127.0.0.1:8000
        p1
        claunchd
        n*:22
        """
        let rows = PortListing.parse(text)
        #expect(rows.map(\.port) == [3000, 8000])
        #expect(rows[0].command == "node")
        #expect(rows[0].pid == 431)
        #expect(rows[1].address == "127.0.0.1:8000")
    }

    @Test func `process list keeps node and python`() {
        let text = """
        120 204800 1.2 /usr/local/bin/node server.js
        121 1024 0.0 /bin/zsh -lic echo
        122 51200 0.4 /opt/homebrew/bin/python3 app.py
        1 100 0.0 /sbin/launchd
        """
        let rows = ProcessListing.parse(text)
        #expect(rows.map(\.pid) == [120, 122])
        #expect(rows[0].memoryMB == 200)
    }

    @Test func `hosts file must keep localhost and reject a bad line`() {
        #expect(HostsFile.problem(in: "127.0.0.1 localhost\n") == nil)
        #expect(HostsFile.problem(in: "::1 localhost ip6-localhost\n") == nil)
        #expect(HostsFile.problem(in: "10.0.0.8 example.test # note\n127.0.0.1 localhost\n") == nil)
        #expect(HostsFile.problem(in: "127.0.0.1 localhost\nnot-an-ip demo.test\n") == "无法识别的地址：not-an-ip")
        #expect(HostsFile.problem(in: "10.0.0.8 example.test\n") == "需要保留 localhost 这一行。")
    }

    @Test func `proxy and env names reject shell syntax`() throws {
        #expect(ProxyDraft.problem(in: "") == nil)
        #expect(ProxyDraft.problem(in: "http://127.0.0.1:7890") == nil)
        #expect(ProxyDraft.problem(in: "http://example.test:8080;rm") != nil)
        #expect(EnvName.problem(in: "API_TOKEN") == nil)
        #expect(EnvName.problem(in: "1TOKEN") != nil)
        let values = try #require(try ProxyDraft.serviceEnvironment(
            http: "http://127.0.0.1:7890",
            https: "  ",
            all: "",
            bypass: "localhost"
        ).get())
        #expect(values["http_proxy"] == "http://127.0.0.1:7890")
        #expect(values["NO_PROXY"] == "localhost")
        #expect(values["https_proxy"] == nil)
        #expect(values["ALL_PROXY"] == nil)
        let rejected = ProxyDraft.serviceEnvironment(http: "http://bad;rm", https: "", all: "", bypass: "")
        #expect(rejected == .failure(ToolError("代理地址里有不能用在终端环境变量里的字符。")))
    }

    @Test func `hosts command reads the pipe before the process exits`() {
        let started = Date()
        let result = HostsFile.collect(
            executable: "/bin/zsh",
            arguments: ["-c", "/usr/bin/python3 -c 'print(\"x\"*80000, end=\"\")'"]
        )
        #expect(Date().timeIntervalSince(started) < 8)
        #expect(result.status == 0)
        #expect(result.text.count == 80_000)
    }

    @Test func `json timestamp and base64 round trip`() throws {
        let pretty = try #require(try DevTransforms.formatJSON("{\"b\":1,\"a\":2}", pretty: true).get())
        #expect(pretty.contains("\"a\" : 2") || pretty.contains("\"a\": 2"))
        let stamp = try #require(try DevTransforms.timestamp("0").get())
        #expect(!stamp.isEmpty)
        let encoded = DevTransforms.base64Encode("MacBJ")
        #expect(try DevTransforms.base64Decode(encoded).get() == "MacBJ")
        #expect(try DevTransforms.urlDecode(DevTransforms.urlEncode("a b")).get() == "a b")
    }

    @Test func `plugins that start a project are the ones enabled by default`() {
        let enabled = Set(ToolboxPlugin.allCases.filter(\.startsEnabled))
        #expect(enabled == [.ports, .processes, .services])
    }

    @Test func `port and process listings read the live system`() async {
        let ports = await PortListing.load()
        #expect((try? ports.get()) != nil)
        let processes = await ProcessListing.load()
        #expect((try? processes.get()) != nil)
    }

    @Test func `quit stop ignores pid 1 and this process`() {
        let started = Date()
        ProcessSignal.stopTreeNow(pid: 1)
        ProcessSignal.stopTreeNow(pid: ProcessInfo.processInfo.processIdentifier)
        #expect(Date().timeIntervalSince(started) < 1)
    }
}
