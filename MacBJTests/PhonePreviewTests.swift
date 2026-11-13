import Foundation
import Testing
@testable import MacBJ

struct PhonePreviewTests {
    @Test("jpeg frames are cut on markers and a bare pair is dropped")
    func jpegFramesAreCutOnMarkersAndABarePairIsDropped() {
        let picture = tinyJPEG(width: 2, height: 3)
        var split = PhoneFrameBuffer()
        #expect(split.feed(Data("junk".utf8) + picture.prefix(8)).isEmpty)
        let frames = split.feed(picture.dropFirst(8) + Data([0x00]))
        #expect(frames.count == 1)
        #expect(frames.first?.starts(with: Data([0xFF, 0xD8])) == true)
        #expect(PhoneFrameBuffer.dimensions(frames[0])?.width == 2)
        #expect(PhoneFrameBuffer.dimensions(frames[0])?.height == 3)
        var bare = PhoneFrameBuffer()
        #expect(bare.feed(Data([0xFF, 0xD8, 0xFF, 0xD9])).isEmpty)
    }

    @Test("the preview command stays on the usb stream and leaves secrets out")
    func thePreviewCommandStaysOnTheUsbStreamAndLeavesSecretsOut() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let checkout = root.appendingPathComponent("checkout", isDirectory: true)
        let runtime = root.appendingPathComponent("state/runtime/forward/node_modules/appium-ios-device", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkout.appendingPathComponent("tooling"), withIntermediateDirectories: true)
        try Data("stream".utf8).write(to: checkout.appendingPathComponent("tooling/screen-stream.mjs"))
        let node = root.appendingPathComponent("node")
        try Data().write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let config: [String: Any] = [
            "udid": "ABCDEFGH1234",
            "team_id": "SECRETTEAM",
            "owner_token": "SECRETTOKEN",
            "mjpeg_device_port": 9100,
        ]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: root.appendingPathComponent("state/config.json"))
        let command = try #require(PhonePreviewLaunch.command(
            stateDir: root.appendingPathComponent("state"),
            checkout: checkout,
            node: node.path
        ))
        #expect(command[0] == node.path)
        #expect(command[2] == "ABCDEFGH1234")
        #expect(command[3] == "9100")
        #expect(!command.joined(separator: " ").contains("SECRET"))
        let copied = try String(contentsOf: root.appendingPathComponent("state/runtime/forward/screen-stream.mjs"), encoding: .utf8)
        #expect(copied == "stream")
        try data.write(to: root.appendingPathComponent("state/config.json"))
        var broken = config
        broken["udid"] = "nope"
        try JSONSerialization.data(withJSONObject: broken).write(to: root.appendingPathComponent("state/config.json"))
        #expect(PhonePreviewLaunch.command(stateDir: root.appendingPathComponent("state"), checkout: checkout, node: node.path) == nil)
        try? FileManager.default.removeItem(at: root)
    }
}

private func tinyJPEG(width: Int, height: Int) -> Data {
    var data = Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x11, 0x08])
    data.append(UInt8((height >> 8) & 0xFF))
    data.append(UInt8(height & 0xFF))
    data.append(UInt8((width >> 8) & 0xFF))
    data.append(UInt8(width & 0xFF))
    data.append(contentsOf: [0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x00, 0x03, 0x11, 0x00, 0xFF, 0xD9])
    return data
}
