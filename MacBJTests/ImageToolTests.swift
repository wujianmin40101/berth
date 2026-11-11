import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MacBJ

struct ImageToolTests {
    @Test("image tools stay off until they are enabled")
    func imageToolsStayOffUntilTheyAreEnabled() {
        #expect(!ToolboxPlugin.images.startsEnabled)
        let enabled = ToolboxPlugin.allCases.filter(\.startsEnabled)
        #expect(!enabled.contains(.images))
        #expect(enabled == [.ports, .processes, .services])
    }

    @Test("image formats stay on the allow list")
    func imageFormatsStayOnTheAllowList() {
        #expect(ImageFileKind.match(extension: "JPG") == .jpeg)
        #expect(ImageFileKind.match(extension: "jpeg") == .jpeg)
        #expect(ImageFileKind.match(extension: "png") == .png)
        #expect(ImageFileKind.match(extension: "HEIC") == .heic)
        #expect(ImageFileKind.match(extension: "heif") == .heic)
        #expect(ImageFileKind.match(extension: "webp") == .webp)
        #expect(ImageFileKind.match(extension: "tif") == .tiff)
        #expect(ImageFileKind.match(extension: "tiff") == .tiff)
        #expect(ImageFileKind.match(extension: "gif") == nil)
        #expect(ImageFileKind.match(extension: "bmp") == nil)
        #expect(ImageFileKind.match(extension: "pdf") == nil)
        #expect(ImageFileKind.match(extension: "") == nil)
        #expect(ImageFileKind.convertOutputs == [.jpeg, .png, .webp])
        #expect(!ImageFileKind.heic.isConvertOutput)
        #expect(!ImageFileKind.tiff.isConvertOutput)
        #expect(ImageJob.mediumQuality == 0.7)
    }

    @Test("stitch is rejected when fewer than two images")
    func stitchIsRejectedWhenFewerThanTwoImages() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("photo.png")
        try writeSquare(to: photo)
        let before = try Data(contentsOf: photo)
        let job = ImageJob(sources: [photo], mode: .stitch)
        #expect(ImageWorkbench.validate(job) == .stitchNeedsTwo)
        let result = ImageWorkbench.perform(job)
        #expect(result == .failure(.stitchNeedsTwo))
        #expect(try Data(contentsOf: photo) == before)
        #expect(try fileNames(in: directory) == ["photo.png"])
    }

    @Test("an empty watermark is rejected")
    func anEmptyWatermarkIsRejected() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a.png")
        let second = directory.appendingPathComponent("b.png")
        try writeSquare(to: first, red: 0.2)
        try writeSquare(to: second, red: 0.8)
        let before = [try Data(contentsOf: first), try Data(contentsOf: second)]
        for text in ["", "   ", "\n"] {
            let job = ImageJob(sources: [first, second], mode: .watermark, watermark: text)
            #expect(ImageWorkbench.validate(job) == .emptyWatermark)
            #expect(ImageWorkbench.perform(job) == .failure(.emptyWatermark))
        }
        #expect(try Data(contentsOf: first) == before[0])
        #expect(try Data(contentsOf: second) == before[1])
        #expect(try fileNames(in: directory) == ["a.png", "b.png"])
    }

    @Test("save as does not overwrite the original")
    func saveAsDoesNotOverwriteTheOriginal() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("photo.png")
        try writeSquare(to: photo, red: 0.1, green: 0.6, blue: 0.3)
        let original = try Data(contentsOf: photo)
        let occupied = directory.appendingPathComponent("photo-compressed.png")
        try Data("keep".utf8).write(to: occupied)

        var reserved: Set<String> = []
        let planned = try #require(
            ImageWorkbench.saveAsURL(for: photo, suffix: "-compressed", ext: "png", reserved: &reserved)
        )
        #expect(planned.lastPathComponent == "photo-compressed-2.png")
        #expect(planned.standardizedFileURL.path != photo.standardizedFileURL.path)

        #expect(try Data(contentsOf: photo) == original)
        #expect(try Data(contentsOf: occupied) == Data("keep".utf8))

        let gif = directory.appendingPathComponent("note.gif")
        try Data("gif".utf8).write(to: gif)
        let names = try fileNames(in: directory)
        #expect(ImageWorkbench.perform(ImageJob(sources: [gif], mode: .compress)) == .failure(.unsupported("note.gif")))
        #expect(try fileNames(in: directory) == names)
    }

    @Test("compress writes a file only when it is smaller")
    func compressWritesAFileOnlyWhenItIsSmaller() throws {
        #expect(!ImageWorkbench.isSmaller(encodedBytes: 20, than: 20))
        #expect(!ImageWorkbench.isSmaller(encodedBytes: 21, than: 20))
        #expect(ImageWorkbench.isSmaller(encodedBytes: 19, than: 20))

        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try #require(patternedImage(size: 64))
        let large = try #require(ImageWorkbench.encode(image, as: .jpeg, quality: 1))
        let small = try #require(ImageWorkbench.encode(image, as: .jpeg, quality: 0.1))
        #expect(small.count < large.count)

        let roomy = directory.appendingPathComponent("roomy.jpg")
        let tight = directory.appendingPathComponent("tight.jpg")
        try large.write(to: roomy)
        try small.write(to: tight)

        let shrunk = try ImageWorkbench.perform(
            ImageJob(sources: [roomy], mode: .compress, quality: 0.1, save: .saveAs)
        ).get()
        #expect(shrunk.written.count == 1)
        #expect(shrunk.written[0].pathExtension == "jpg")
        #expect(shrunk.written[0].standardizedFileURL.path != roomy.standardizedFileURL.path)
        let saved = try Data(contentsOf: shrunk.written[0])
        #expect(saved.count < large.count)
        #expect(try Data(contentsOf: roomy) == large)
        #expect(pixelSize(shrunk.written[0]) != nil)

        let grown = ImageWorkbench.compressedByteCount(at: tight, quality: 1)
        #expect(try #require(grown) >= small.count)
        #expect(ImageWorkbench.perform(
            ImageJob(sources: [tight], mode: .compress, quality: 1, save: .saveAs)
        ) == .failure(.notSmaller))
        #expect(try Data(contentsOf: tight) == small)
        #expect(ImageWorkbench.perform(
            ImageJob(sources: [tight], mode: .compress, quality: 1, save: .overwrite)
        ) == .failure(.notSmaller))
        #expect(try Data(contentsOf: tight) == small)

        let roomyPreview = try #require(ImageWorkbench.compressedByteCount(at: roomy, quality: 0.1))
        #expect(roomyPreview < large.count)
        let tightPreview = try #require(ImageWorkbench.compressedByteCount(at: tight, quality: 0.1))
        let mixed = try ImageWorkbench.perform(
            ImageJob(sources: [roomy, tight], mode: .compress, quality: 0.1, save: .saveAs)
        ).get()
        #expect(try Data(contentsOf: roomy) == large)
        #expect(try Data(contentsOf: tight) == small)
        if tightPreview < small.count {
            #expect(mixed.written.count == 2)
            #expect(mixed.skippedNotSmaller == 0)
        } else {
            #expect(mixed.skippedNotSmaller == 1)
            #expect(mixed.written.count == 1)
            #expect(mixed.written[0].lastPathComponent.contains("roomy"))
        }
    }

    @Test("stitch writes one new image and leaves the originals")
    func stitchWritesOneNewImageAndLeavesTheOriginals() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("left.png")
        let second = directory.appendingPathComponent("right.png")
        try writeSquare(to: first, red: 1, size: 8)
        try writeSquare(to: second, red: 0, size: 8)
        let before = [try Data(contentsOf: first), try Data(contentsOf: second)]
        let stitched = try ImageWorkbench.perform(
            ImageJob(sources: [first, second], mode: .stitch, axis: .horizontal)
        ).get()
        #expect(stitched.written.count == 1)
        #expect(stitched.written[0].pathExtension == "png")
        #expect(try #require(pixelSize(stitched.written[0])) == (16, 8))
        #expect(try Data(contentsOf: first) == before[0])
        #expect(try Data(contentsOf: second) == before[1])

        let down = try ImageWorkbench.perform(
            ImageJob(sources: [first, second], mode: .stitch, axis: .vertical)
        ).get()
        #expect(try #require(pixelSize(down.written[0])) == (8, 16))
        #expect(try Data(contentsOf: first) == before[0])
        #expect(try Data(contentsOf: second) == before[1])
    }

    @Test("a failed read does not corrupt the original")
    func aFailedReadDoesNotCorruptTheOriginal() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = directory.appendingPathComponent("broken.png")
        let bytes = Data("not an image".utf8)
        try bytes.write(to: photo)
        let overwrite = ImageJob(sources: [photo], mode: .compress, save: .overwrite)
        #expect(ImageWorkbench.perform(overwrite) == .failure(.unreadable("broken.png")))
        #expect(try Data(contentsOf: photo) == bytes)
        #expect(try fileNames(in: directory) == ["broken.png"])
    }

    @Test("the first opening is remembered")
    func theFirstOpeningIsRemembered() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: OpeningStore.playedKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: OpeningStore.playedKey)
            } else {
                defaults.removeObject(forKey: OpeningStore.playedKey)
            }
        }
        defaults.removeObject(forKey: OpeningStore.playedKey)
        #expect(!OpeningStore.hasPlayed)
        OpeningStore.markPlayed()
        #expect(OpeningStore.hasPlayed)
    }
}

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("berth-images-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func patternedImage(size: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    for y in 0..<size {
        for x in 0..<size {
            let n = (x * 17 + y * 31) % 256
            context.setFillColor(
                red: CGFloat(n) / 255,
                green: CGFloat((n * 3) % 256) / 255,
                blue: CGFloat((n * 7) % 256) / 255,
                alpha: 1
            )
            context.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return context.makeImage()
}

private func writeSquare(
    to url: URL,
    red: CGFloat = 0.4,
    green: CGFloat = 0.2,
    blue: CGFloat = 0.7,
    size: Int = 8
) throws {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        Issue.record("could not draw")
        return
    }
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(size), height: CGFloat(size)))
    let image = try #require(context.makeImage())
    let data = try #require(ImageWorkbench.encode(image, as: .png, quality: 1))
    try data.write(to: url)
}

private func fileNames(in directory: URL) throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent))
}

private func pixelSize(_ url: URL) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return nil
    }
    let width = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let height = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    guard width > 0, height > 0 else { return nil }
    return (width, height)
}
