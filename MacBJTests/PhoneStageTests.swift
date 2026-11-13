import Foundation
import Testing
@testable import MacBJ

struct PhoneStageTests {
    @Test("screen state, shots, and jobs stay free of secrets")
    func screenStateShotsAndJobsStayFreeOfSecrets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("jobs"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("artifacts"), withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_794_551_470)
        let fresh = Int(now.timeIntervalSince1970 * 1000) - 400
        let stale = fresh - 20_000
        let screen: [String: Any] = [
            "paused": false,
            "model": "iPhone 16 Pro",
            "viewport": ["width": 393.0, "height": 852.0],
            "finished_at": fresh,
            "actors": [:],
            "events": [
                ["id": 7, "kind": "tap", "at": fresh, "point": ["x": 26.0, "y": 81.0], "viewport": ["width": 393.0, "height": 852.0]],
                ["id": 4, "kind": "drag", "at": stale, "from": ["x": 10.0, "y": 20.0], "to": ["x": 40.0, "y": 80.0], "viewport": ["width": 393.0, "height": 852.0]],
            ],
        ]
        try write(screen, root.appendingPathComponent("screen-state.json"))
        try write([
            "udid": "SHOULD-NOT-APPEAR",
            "team_id": "SECRETTEAM",
            "bundle_id": "com.example.runner",
            "local_port": 18100,
            "source_dir": root.appendingPathComponent("runtime/WebDriverAgent").path,
        ], root.appendingPathComponent("config.json"))
        try write([
            "url": "http://127.0.0.1:18100",
            "session_id": "SESSION",
        ], root.appendingPathComponent("session.json"))
        try write([
            "id": "job-1",
            "action": "recover",
            "state": "running",
            "recovery_phase": "starting",
            "owner_token": "SECRETTOKEN",
            "created_at": "2026-11-13T06:20:04.000000+00:00",
            "error": "",
        ], root.appendingPathComponent("jobs/job-1.json"))
        let stem = root.appendingPathComponent("artifacts/20261113T063111040623Z-aaaaaaaa")
        try Data([0x89]).write(to: stem.appendingPathExtension("png"))
        try Data([0xFF]).write(to: stem.appendingPathExtension("jpg"))
        try Data([0x89]).write(to: root.appendingPathComponent("artifacts/header-name.png"))

        let stage = PhoneStage.load(directory: root, now: now)
        #expect(stage.shell == .island)
        #expect(stage.live == .cached)
        #expect(stage.operating)
        #expect(stage.port == 18100)
        #expect(stage.bundleID == "com.example.runner")
        #expect(stage.endpoint == "127.0.0.1:18100")
        #expect(stage.sessionOpen)
        #expect(stage.pages.map(\.name) == ["20261113T063111040623Z-aaaaaaaa.png"])
        #expect(stage.pages.first?.stamp == "06:31:11")
        #expect(stage.crops.map(\.name) == ["header-name.png"])
        #expect(stage.droppedTwins == 1)
        #expect(stage.gestures.map(\.id) == [7])
        #expect(stage.recorded.map(\.id) == [4, 7])
        #expect(stage.recoveryPhase == "starting")
        #expect(!stage.exposed.contains("SECRETTEAM"))
        #expect(!stage.exposed.contains("SECRETTOKEN"))
        #expect(!stage.exposed.contains("SHOULD-NOT-APPEAR"))
        try? FileManager.default.removeItem(at: root)
    }

    @Test("punch log steps include opening attendance and switching accounts")
    func punchLogStepsIncludeOpeningAttendanceAndSwitchingAccounts() {
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let utc = DateFormatter()
        utc.locale = Locale(identifier: "en_US_POSIX")
        utc.timeZone = TimeZone(secondsFromGMT: 0)
        utc.dateFormat = "yyyyMMdd'T'HHmmss"
        let tappedAt = local.date(from: "2026-11-13 14:09:39") ?? Date()
        let name = utc.string(from: tappedAt) + "000000Z-abc.png"
        let shot = PhoneShot(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, stamp: "tap", crop: false)
        let log = """
        2026-11-13 14:09:35 opened 假勤 at (212, 393)
        2026-11-13 14:09:38 page punch-button
        2026-11-13 14:09:39 tapped punch-button at (196, 468)
        2026-11-13 14:09:41 page not-ready
        2026-11-13 14:27:29 ocr 吴建民
        2026-11-13 14:27:49 switch 吴建民 -> 陈家斌 -> 吴建民
        2026-11-13 14:35:28 installed com.iphone-use.punch-in
        """
        let steps = PhoneStage.traces(log: log, shots: [shot])
        #expect(steps.map(\.kind) == ["open", "page", "tap", "recognize", "switch"])
        #expect(steps[0].x == 212)
        #expect(steps[0].y == 393)
        #expect(steps[0].shot == shot.url)
        #expect(steps[2].detail == "punch-button")
        #expect(steps[2].x == 196)
        #expect(steps[2].shot == shot.url)
        #expect(steps[4].detail == "吴建民 -> 陈家斌 -> 吴建民")
        #expect(steps[4].shot == nil)
    }

    @Test("shell follows the confirmed model name")
    func shellFollowsTheConfirmedModelName() {
        #expect(PhoneStage.shell(for: "iPhone 16 Pro") == .island)
        #expect(PhoneStage.shell(for: "iPhone 14") == .rounded)
        #expect(PhoneStage.shell(for: "iPhone SE") == .plain)
        #expect(PhoneStage.shell(for: "") == .plain)
    }

    @Test("a lock pause is kept and an unknown reason is not trusted")
    func aLockPauseIsKeptAndAnUnknownReasonIsNotTrusted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(["paused": true, "pause_reason": "device_locked"], root.appendingPathComponent("screen-state.json"))
        let locked = PhoneStage.load(directory: root)
        #expect(locked.paused)
        #expect(locked.pauseReason == "device_locked")
        #expect(locked.live == .paused)
        try write(["paused": true, "pause_reason": "something-else"], root.appendingPathComponent("screen-state.json"))
        let unknown = PhoneStage.load(directory: root)
        #expect(unknown.pauseReason == "unknown")
        try? FileManager.default.removeItem(at: root)
    }

    @Test("opening attendance marks the fixed shortcut above the message list")
    func openingAttendanceMarksTheFixedShortcutAboveTheMessageList() {
        let shortcut = PhoneTextSpot(text: "假勤", x: 268.0 / 3, y: 873.0 / 3, width: 71.0 / 3, height: 41.0 / 3)
        let spots = [
            PhoneTextSpot(text: "豆包工作", x: 41.0 / 3, y: 877.0 / 3, width: 134.0 / 3, height: 37.0 / 3),
            shortcut,
            PhoneTextSpot(text: "维拉工时", x: 423.0 / 3, y: 875.0 / 3, width: 135.0 / 3, height: 41.0 / 3),
            PhoneTextSpot(text: "消息", x: 234.0 / 3, y: 1007.0 / 3, width: 85.0 / 3, height: 45.0 / 3),
            PhoneTextSpot(text: "假勤", x: 72, y: 518, width: 36, height: 16),
            PhoneTextSpot(text: "消息", x: 21, y: 795, width: 21, height: 12),
        ]
        let point = PhoneScreenText.pinnedPoint(spots)
        #expect(point?.x == shortcut.x + shortcut.width / 2)
        #expect(point?.y == shortcut.y - 30)
        #expect(PhoneScreenText.pinnedPoint([
            PhoneTextSpot(text: "消息", x: 70, y: 390, width: 36, height: 20),
            PhoneTextSpot(text: "假勤", x: 72, y: 430, width: 36, height: 16),
        ]) == nil)
        let home = URL(fileURLWithPath: "/tmp/home.png")
        let steps = PhoneStage.traces(
            log: "2026-11-13 14:09:35 opened 假勤 at (212, 393)\n",
            shots: [],
            pinned: (home, point?.x ?? 0, point?.y ?? 0)
        )
        #expect(steps.first?.shot == home)
        #expect(steps.first?.x == point?.x)
        #expect(steps.first?.y != 393)
    }

    private func write(_ json: [String: Any], _ url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: url)
    }
}
