import Testing
@testable import MacBJ

struct NvmdTests {
    @Test func `commands parse the nvmd verbs`() {
        #expect(NvmdArguments.parse(["list"]) == .command(.list))
        #expect(NvmdArguments.parse(["nvmd", "current"]) == .command(.current))
        #expect(NvmdArguments.parse(["install", "v22.23.4"]) == .command(.install("v22.23.4")))
        #expect(NvmdArguments.parse(["uninstall", "20.20.2"]) == .command(.uninstall("20.20.2")))
        #expect(NvmdArguments.parse(["use", "22.23.4"]) == .command(.use(version: "22.23.4", project: false)))
        #expect(NvmdArguments.parse(["use", "22.23.4", "--project"]) == .command(.use(version: "22.23.4", project: true)))
        #expect(NvmdArguments.parse(["use", "--project", "v20.20.2"]) == .command(.use(version: "v20.20.2", project: true)))
        #expect(NvmdArguments.parse(["which"]) == .command(.which("node")))
        #expect(NvmdArguments.parse(["which", "npm"]) == .command(.which("npm")))
    }

    @Test func `unknown commands and extra arguments fail`() {
        #expect(NvmdArguments.parse(["deploy"]) == .rejected(L("没有这个命令: %@", "deploy")))
        #expect(NvmdArguments.parse(["list", "all"]) == .rejected(L("list 不接受参数。")))
        #expect(NvmdArguments.parse(["use"]) == .rejected(L("用法: nvmd use <版本> [--project]")))
        #expect(NvmdArguments.parse(["which", "python"]) == .rejected(L("用法: nvmd which [node|npm]")))
        #expect(NvmdArguments.parse(["install", "22 23"]) == .rejected(L("用法: nvmd install <版本>")))
    }
}
