import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 图片只在本机读写。这里没有网络请求。
nonisolated enum ImageFileKind: String, CaseIterable, Sendable, Equatable {
    case jpeg
    case png
    case heic
    case webp
    case tiff

    var canonicalExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .webp: "webp"
        case .tiff: "tiff"
        }
    }

    var typeIdentifier: CFString {
        switch self {
        case .jpeg: UTType.jpeg.identifier as CFString
        case .png: UTType.png.identifier as CFString
        case .heic: UTType.heic.identifier as CFString
        case .webp: UTType.webP.identifier as CFString
        case .tiff: UTType.tiff.identifier as CFString
        }
    }

    var isConvertOutput: Bool {
        switch self {
        case .jpeg, .png, .webp: true
        case .heic, .tiff: false
        }
    }

    static var convertOutputs: [ImageFileKind] { [.jpeg, .png, .webp] }

    static func match(url: URL) -> ImageFileKind? {
        match(extension: url.pathExtension)
    }

    static func match(extension raw: String) -> ImageFileKind? {
        switch raw.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "png": .png
        case "heic", "heif": .heic
        case "webp": .webp
        case "tif", "tiff": .tiff
        default: nil
        }
    }
}

nonisolated enum ImageToolMode: String, CaseIterable, Sendable, Equatable {
    case compress
    case convert
    case stitch
    case watermark

    var title: String {
        switch self {
        case .compress: L("压缩")
        case .convert: L("转格式")
        case .stitch: L("拼接")
        case .watermark: L("加水印")
        }
    }
}

nonisolated enum ImageStitchAxis: String, CaseIterable, Sendable, Equatable {
    case horizontal
    case vertical

    var title: String {
        switch self {
        case .horizontal: L("横向")
        case .vertical: L("纵向")
        }
    }
}

nonisolated enum ImageSaveMode: String, Sendable, Equatable {
    case saveAs
    case overwrite
}

nonisolated struct ImageJob: Sendable, Equatable {
    var sources: [URL]
    var mode: ImageToolMode
    var quality: Double = ImageJob.mediumQuality
    var output: ImageFileKind = .jpeg
    var axis: ImageStitchAxis = .horizontal
    var watermark: String = ""
    var save: ImageSaveMode = .saveAs

    /// 中等质量。滑杆可以改，范围收在 0.1 到 1。
    static let mediumQuality = 0.7

    static func clampedQuality(_ value: Double) -> Double {
        min(1, max(0.1, value))
    }
}

nonisolated enum ImageRefusal: Error, Equatable, Sendable {
    case unsupported(String)
    case stitchNeedsTwo
    case emptyWatermark
    case unreadable(String)
    case unwritable(String)
    case notSmaller

    var text: String {
        switch self {
        case .unsupported(let name):
            L("这种格式不能处理：%@", name)
        case .stitchNeedsTwo:
            L("拼接至少需要两张图片。")
        case .emptyWatermark:
            L("先写水印文字。")
        case .unreadable(let name):
            L("没有读到这张图片：%@", name)
        case .unwritable(let name):
            L("没有保存：%@", name)
        case .notSmaller:
            L("按当前质量压不小，没有写出更大的文件。")
        }
    }
}

nonisolated struct ImageWrite: Equatable, Sendable {
    var sources: [URL]
    var written: [URL]
    var skippedNotSmaller = 0
}

/// 工程默认隔离是 MainActor。压缩和缩略图在后台任务里跑，所以这个类型保持非隔离。
nonisolated enum ImageWorkbench {
    static func validate(_ job: ImageJob) -> ImageRefusal? {
        if job.sources.isEmpty { return nil }
        for url in job.sources {
            if ImageFileKind.match(url: url) == nil {
                return .unsupported(url.lastPathComponent)
            }
        }
        switch job.mode {
        case .stitch where job.sources.count < 2:
            return .stitchNeedsTwo
        case .watermark where job.watermark.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .emptyWatermark
        case .convert where !job.output.isConvertOutput:
            return .unwritable(job.output.canonicalExtension)
        default:
            return nil
        }
    }

    static func perform(
        _ job: ImageJob,
        progress: (@Sendable (Double) -> Void)? = nil
    ) -> Result<ImageWrite, ImageRefusal> {
        if let refusal = validate(job) {
            return .failure(refusal)
        }
        var job = job
        job.quality = ImageJob.clampedQuality(job.quality)
        if job.mode == .stitch {
            job.save = .saveAs
            return stitch(job, progress: progress)
        }
        return each(job, progress: progress)
    }

    static func thumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        read(at: url, maxPixel: maxPixel)
    }

    /// 压缩后的字节必须更少。一样大也不写。
    static func isSmaller(encodedBytes: Int, than originalBytes: Int) -> Bool {
        encodedBytes < originalBytes
    }

    static func byteCount(at url: URL) -> Int? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    /// 只在内存里重编码，用来预估压缩后的大小。不写文件。
    static func compressedByteCount(at url: URL, quality: Double) -> Int? {
        guard let kind = ImageFileKind.match(url: url),
              let image = read(at: url, maxPixel: nil),
              let data = encode(image, as: kind, quality: ImageJob.clampedQuality(quality)) else {
            return nil
        }
        return data.count
    }

    private static func each(
        _ job: ImageJob,
        progress: (@Sendable (Double) -> Void)?
    ) -> Result<ImageWrite, ImageRefusal> {
        var written: [URL] = []
        var reserved: Set<String> = []
        var skippedNotSmaller = 0
        let total = Double(job.sources.count)
        for (index, source) in job.sources.enumerated() {
            progress?(Double(index) / total)
            guard let image = read(at: source, maxPixel: nil) else {
                return .failure(.unreadable(source.lastPathComponent))
            }
            let kind = outputKind(for: job, source: source)
            let rendered: CGImage?
            switch job.mode {
            case .watermark:
                let text = job.watermark.trimmingCharacters(in: .whitespacesAndNewlines)
                rendered = watermark(image, text: text)
            default:
                rendered = image
            }
            guard let rendered, let data = encode(rendered, as: kind, quality: job.quality) else {
                return .failure(.unwritable(source.lastPathComponent))
            }
            if job.mode == .compress {
                guard let originalBytes = byteCount(at: source) else {
                    return .failure(.unreadable(source.lastPathComponent))
                }
                if !isSmaller(encodedBytes: data.count, than: originalBytes) {
                    skippedNotSmaller += 1
                    continue
                }
            }
            let destination: URL
            if job.save == .overwrite {
                destination = source
            } else {
                guard let url = saveAsURL(
                    for: source,
                    suffix: suffix(for: job, source: source, output: kind),
                    ext: kind.canonicalExtension,
                    reserved: &reserved
                ) else {
                    return .failure(.unwritable(source.lastPathComponent))
                }
                destination = url
            }
            if destination.standardizedFileURL.path == source.standardizedFileURL.path, job.save != .overwrite {
                return .failure(.unwritable(source.lastPathComponent))
            }
            if let refusal = commit(data, to: destination, replacing: job.save == .overwrite) {
                return .failure(refusal)
            }
            written.append(destination)
        }
        progress?(1)
        if written.isEmpty, skippedNotSmaller > 0 {
            return .failure(.notSmaller)
        }
        return .success(ImageWrite(sources: job.sources, written: written, skippedNotSmaller: skippedNotSmaller))
    }

    private static func stitch(
        _ job: ImageJob,
        progress: (@Sendable (Double) -> Void)?
    ) -> Result<ImageWrite, ImageRefusal> {
        guard let first = job.sources.first else {
            return .failure(.stitchNeedsTwo)
        }
        var images: [CGImage] = []
        let total = Double(job.sources.count)
        for (index, source) in job.sources.enumerated() {
            progress?(Double(index) / total * 0.8)
            guard let image = read(at: source, maxPixel: nil) else {
                return .failure(.unreadable(source.lastPathComponent))
            }
            images.append(image)
        }
        guard let combined = combine(images, axis: job.axis),
              let data = encode(combined, as: .png, quality: 1) else {
            return .failure(.unwritable(first.lastPathComponent))
        }
        var reserved: Set<String> = []
        guard let destination = saveAsURL(for: first, suffix: "-stitched", ext: "png", reserved: &reserved) else {
            return .failure(.unwritable(first.lastPathComponent))
        }
        if let refusal = commit(data, to: destination, replacing: false) {
            return .failure(refusal)
        }
        progress?(1)
        return .success(ImageWrite(sources: job.sources, written: [destination]))
    }

    private static func outputKind(for job: ImageJob, source: URL) -> ImageFileKind {
        switch job.mode {
        case .convert:
            job.output
        case .stitch:
            .png
        default:
            ImageFileKind.match(url: source) ?? .png
        }
    }

    private static func suffix(for job: ImageJob, source: URL, output: ImageFileKind) -> String {
        switch job.mode {
        case .compress:
            "-compressed"
        case .watermark:
            "-watermark"
        case .stitch:
            "-stitched"
        case .convert:
            ImageFileKind.match(url: source) == output ? "-converted" : ""
        }
    }

    /// 另存为绝不返回原路径。同名文件已存在时改用 -2、-3。
    static func saveAsURL(
        for source: URL,
        suffix: String,
        ext: String,
        reserved: inout Set<String>
    ) -> URL? {
        let folder = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        let sourcePath = source.standardizedFileURL.path
        var extra = ""
        var number = 2
        while number < 1000 {
            let url = folder.appendingPathComponent("\(stem)\(suffix)\(extra).\(ext)")
            let path = url.standardizedFileURL.path
            let taken = path == sourcePath || reserved.contains(path) || FileManager.default.fileExists(atPath: path)
            if !taken {
                reserved.insert(path)
                return url
            }
            extra = "-\(number)"
            number += 1
        }
        return nil
    }

    private static func commit(_ data: Data, to destination: URL, replacing: Bool) -> ImageRefusal? {
        let folder = destination.deletingLastPathComponent()
        let temp = folder.appendingPathComponent(".berth-\(UUID().uuidString).partial")
        do {
            try data.write(to: temp, options: .atomic)
            if replacing {
                if FileManager.default.fileExists(atPath: destination.path) {
                    _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
                } else {
                    try FileManager.default.moveItem(at: temp, to: destination)
                }
            } else if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: temp)
                return .unwritable(destination.lastPathComponent)
            } else {
                try FileManager.default.moveItem(at: temp, to: destination)
            }
            return nil
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return .unwritable(destination.lastPathComponent)
        }
    }

    static func read(at url: URL, maxPixel: Int?) -> CGImage? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let limit = maxPixel ?? pixelLimit(of: source)
        guard limit > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: limit,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }
        let cache: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateImageAtIndex(source, 0, cache as CFDictionary)
    }

    private static func pixelLimit(of source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return 1
        }
        let width = intValue(props[kCGImagePropertyPixelWidth])
        let height = intValue(props[kCGImagePropertyPixelHeight])
        return max(width, height, 1)
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return 0
    }

    static func encode(_ image: CGImage, as kind: ImageFileKind, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, kind.typeIdentifier, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if kind != .png {
            properties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func combine(_ images: [CGImage], axis: ImageStitchAxis) -> CGImage? {
        guard images.count >= 2 else { return nil }
        let width: Int
        let height: Int
        switch axis {
        case .horizontal:
            width = images.reduce(0) { $0 + $1.width }
            height = images.map(\.height).max() ?? 0
        case .vertical:
            width = images.map(\.width).max() ?? 0
            height = images.reduce(0) { $0 + $1.height }
        }
        guard let context = context(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        switch axis {
        case .horizontal:
            var x: CGFloat = 0
            for image in images {
                let y = CGFloat(height - image.height) / 2
                context.draw(
                    image,
                    in: CGRect(x: x, y: y, width: CGFloat(image.width), height: CGFloat(image.height))
                )
                x += CGFloat(image.width)
            }
        case .vertical:
            var top = CGFloat(height)
            for image in images {
                top -= CGFloat(image.height)
                let x = CGFloat(width - image.width) / 2
                context.draw(
                    image,
                    in: CGRect(x: x, y: top, width: CGFloat(image.width), height: CGFloat(image.height))
                )
            }
        }
        return context.makeImage()
    }

    private static func watermark(_ image: CGImage, text: String) -> CGImage? {
        guard let context = context(width: image.width, height: image.height) else { return nil }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        )
        let fontSize = max(16, CGFloat(min(image.width, image.height)) / 22)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let margin = fontSize
        drawLine(
            text,
            font: font,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55),
            in: context,
            at: CGPoint(x: margin + 1, y: margin - 1)
        )
        drawLine(
            text,
            font: font,
            color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.94),
            in: context,
            at: CGPoint(x: margin, y: margin)
        )
        return context.makeImage()
    }

    private static func drawLine(
        _ text: String,
        font: CTFont,
        color: CGColor,
        in context: CGContext,
        at point: CGPoint
    ) {
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else {
            return
        }
        let line = CTLineCreateWithAttributedString(attributed)
        context.textMatrix = .identity
        context.textPosition = point
        CTLineDraw(line, context)
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        guard width > 0, height > 0, width <= 40_000, height <= 40_000 else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
