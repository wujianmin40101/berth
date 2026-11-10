import Foundation
import Testing
@testable import MacBJ

struct MaintenanceTests {
    @Test("memory slices match activity monitor buckets")
    func memorySlicesMatchActivityMonitorBuckets() {
        let counts = MemoryCounts(
            pageSize: 16_384,
            free: 400,
            speculative: 50,
            wired: 200,
            compressor: 50,
            purgeable: 100,
            external: 300,
            internalPages: 1_000,
            total: 32 * 1024 * 1024 * 1024
        )
        let slices = MemoryMap.slices(counts)
        #expect(slices.map(\.id) == ["app", "wired", "compressed", "cached", "free"])
        #expect(slices[0].bytes == 900 * 16_384)
        #expect(slices[1].bytes == 200 * 16_384)
        #expect(slices[2].bytes == 50 * 16_384)
        #expect(slices[3].bytes == 400 * 16_384)
        #expect(slices[4].bytes == 450 * 16_384)
    }

    @Test("memory snapshot reads physical memory")
    func memorySnapshotReadsPhysicalMemory() {
        let report = MemoryMap.snapshot()
        #expect(report.total > 0)
        #expect(!report.slices.isEmpty)
        #expect(!report.summary.isEmpty)
    }

    @Test("processes inside one app bundle are grouped")
    func processesInsideOneAppBundleAreGrouped() {
        let rows: [(pid: Int32, bytes: UInt64, cpu: Double, command: String)] = [
            (10, 100, 1.5, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
            (11, 50, 0.5, "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Helper.app/Contents/MacOS/helper"),
            (12, 20, 3, "/usr/local/bin/node server.js")
        ]
        let grouped = MemoryMap.group(rows)
        #expect(grouped.map(\.name) == ["Google Chrome", "node"])
        #expect(grouped[0].bytes == 150)
        #expect(grouped[0].pid == 10)
        #expect(grouped[0].cpu == 2)
        #expect(grouped[0].path == "/Applications/Google Chrome.app")
        #expect(grouped[1].path == "/usr/local/bin/node")
    }

    @Test("leftovers stay on the bundle id and drop shared names")
    func leftoversStayOnTheBundleIdAndDropSharedNames() {
        let library = URL(fileURLWithPath: "/Users/demo/Library")
        let demo = AppUninstall.Identity(name: "Demo", bundleID: "com.example.demo")
        let other = AppUninstall.Identity(name: "Demo", bundleID: "com.example.other")
        let mine = AppUninstall.deletionSet(library: library, app: demo, others: [other]).map(\.path)
        #expect(mine.contains("/Users/demo/Library/Caches/com.example.demo"))
        #expect(mine.contains("/Users/demo/Library/Preferences/com.example.demo.plist"))
        #expect(!mine.contains("/Users/demo/Library/Application Support/Demo"))
        #expect(!mine.contains("/Users/demo/Library/Caches/com.example.other"))
    }

    @Test("bundle ids with a path are rejected")
    func bundleIdsWithAPathAreRejected() {
        #expect(!AppUninstall.safeToken("../Library"))
        #expect(!AppUninstall.safeToken("com.example/evil"))
        #expect(AppUninstall.safeToken("com.example.demo"))
        #expect(AppUninstall.safeName("Google Chrome"))
        #expect(!AppUninstall.safeName("../Chrome"))
    }

    @Test("only a direct app in Applications can be uninstalled")
    func onlyADirectAppInApplicationsCanBeUninstalled() {
        let home = URL(fileURLWithPath: "/Users/demo")
        #expect(AppUninstall.isDirectApp(path: "/Applications/Demo.app", home: home))
        #expect(AppUninstall.isDirectApp(path: "/Users/demo/Applications/Demo.app", home: home))
        #expect(!AppUninstall.isDirectApp(path: "/Applications/Demo.app/Contents/Helpers/Helper.app", home: home))
        #expect(!AppUninstall.isDirectApp(path: "/tmp/Demo.app", home: home))
    }

    @Test("cache deletion refuses a path outside its root")
    func cacheDeletionRefusesAPathOutsideItsRoot() {
        let root = URL(fileURLWithPath: "/Users/demo/Library/Caches")
        #expect(CacheClean.accepts(child: URL(fileURLWithPath: "/Users/demo/Library/Caches/com.example"), root: root))
        #expect(!CacheClean.accepts(child: URL(fileURLWithPath: "/Users/demo/Documents"), root: root))
    }

    @Test("allocated size counts a file and does not follow a symlink")
    func allocatedSizeCountsAFileAndDoesNotFollowASymlink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("macbj-size-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 7, count: 8192).write(to: root.appendingPathComponent("note.txt"))
        let nested = root.appendingPathComponent("sub/deep", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 3, count: 4096).write(to: nested.appendingPathComponent("b.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("jump"), withDestinationURL: URL(fileURLWithPath: "/usr"))
        let scan = AllocatedSize.tree(root.path, deadline: Date().addingTimeInterval(5))
        #expect(scan.complete)
        #expect(scan.bytes >= 12_288)
        #expect(scan.bytes < 1_000_000)
        let sub = scan.children.first { $0.path.hasSuffix("/sub") }
        #expect(sub != nil)
        #expect(sub?.children.contains { $0.path.hasSuffix("/deep") } == true)
        #expect(!scan.children.contains { $0.path.hasSuffix("/jump") })
    }

    @Test("a passed size deadline returns without listing")
    func aPassedSizeDeadlineReturnsWithoutListing() {
        let started = Date()
        let scan = AllocatedSize.tree("/Users", deadline: Date().addingTimeInterval(-1))
        #expect(Date().timeIntervalSince(started) < 3)
        #expect(!scan.complete)
    }

    @Test("du lines keep the path after the tab")
    func duLinesKeepThePathAfterTheTab() {
        let rows = DirectorySize.parse("2315284\t/opt\n1024\t/opt/homebrew\n")
        #expect(rows.map(\.path) == ["/opt", "/opt/homebrew"])
        #expect(rows[0].bytes == 2_315_284 * 1024)
        #expect(DirectorySize.parse("du: /Library/TCC: Operation not permitted\n").isEmpty)
    }

    @Test("spotlight last used date parses and ignores a missing value")
    func spotlightLastUsedDateParsesAndIgnoresAMissingValue() {
        let date = SpotlightDate.parse("2026-11-05 06:54:40 +0000")
        #expect(date != nil)
        #expect(SpotlightDate.parse("-") == nil)
        #expect(SpotlightDate.parse("(null)") == nil)
    }

    @Test("treemap tiles cover the rectangle in proportion")
    func treemapTilesCoverTheRectangleInProportion() {
        let tiles = TreemapLayout.tiles(
            [
                TreemapInput(id: "a", title: "A", value: 200),
                TreemapInput(id: "b", title: "B", value: 100),
                TreemapInput(id: "c", title: "C", value: 100)
            ],
            in: CGRect(x: 0, y: 0, width: 200, height: 100)
        )
        let area = tiles.reduce(0) { $0 + $1.rect.width * $1.rect.height }
        #expect(abs(area - 20_000) < 1)
        #expect(tiles.count == 3)
        #expect(tiles.allSatisfy { $0.rect.width > 0 && $0.rect.height > 0 })
    }

    @Test("launchctl disabled lines use both old and new spellings")
    func launchctlDisabledLinesUseBothOldAndNewSpellings() {
        let text = """
        "com.example.one" => disabled
        "com.example.two" => enabled
        "com.example.old" => true
        "com.example.new" => false
        """
        let parsed = SpeedTune.parseDisabled(text)
        #expect(parsed["com.example.one"] == false)
        #expect(parsed["com.example.two"] == true)
        #expect(parsed["com.example.old"] == false)
        #expect(parsed["com.example.new"] == true)
    }

    @Test("system executables and Berth cannot be stopped")
    func systemExecutablesAndBerthCannotBeStopped() {
        let other: Int32 = ProcessInfo.processInfo.processIdentifier == 42 ? 43 : 42
        #expect(!ProcessGuard.isSystemLocation("/usr/local/bin/node"))
        #expect(!ProcessGuard.isSystemLocation("/opt/homebrew/bin/node"))
        #expect(ProcessGuard.isSystemLocation("/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"))
        #expect(ProcessGuard.isSystemLocation("/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"))
        #expect(ProcessGuard.isSystemLocation("/usr/libexec/syspolicyd"))
        #expect(ProcessGuard.isSystemLocation("/usr/bin/ssh"))
        #expect(ProcessGuard.isSystemLocation("/usr/sbin/syslogd"))
        #expect(ProcessGuard.canStop(pid: other, path: "/usr/local/bin/node"))
        #expect(ProcessGuard.canStop(pid: other, path: "/opt/homebrew/bin/python3"))
        #expect(!ProcessGuard.canStop(pid: other, path: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"))
        #expect(!ProcessGuard.canStop(pid: other, path: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"))
        #expect(!ProcessGuard.canStop(pid: other, path: "/usr/libexec/syspolicyd"))
        #expect(!ProcessGuard.canStop(pid: 1, path: "/usr/local/bin/node"))
        #expect(!ProcessGuard.canStop(pid: other, path: "/Applications/泊位.app/Contents/MacOS/MacBJ"))
    }
}
