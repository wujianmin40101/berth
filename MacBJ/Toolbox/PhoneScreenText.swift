import CoreGraphics
import Foundation
import ImageIO
import Vision

nonisolated struct PhoneTextSpot: Equatable, Sendable {
    var text: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

/// 从页面截图里找出顶部固定的假勤，避开消息列表里会换行的那一条。
nonisolated enum PhoneScreenText {
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var spots: [String: [PhoneTextSpot]] = [:]
    }

    private static let cache = Cache()

    static func pinnedAttendance(
        in pages: [PhoneShot],
        viewportWidth: Double,
        viewportHeight: Double
    ) -> (url: URL, x: Double, y: Double)? {
        for page in pages {
            let spots = recognize(page.url, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
            if let point = pinnedPoint(spots) {
                return (page.url, point.x, point.y)
            }
        }
        return nil
    }

    static func pinnedPoint(_ spots: [PhoneTextSpot]) -> (x: Double, y: Double)? {
        let rows = spots.map { (compact($0.text), $0) }.filter { !$0.0.isEmpty }
        let listTops = rows.compactMap { text, spot -> Double? in
            guard text == "消息" || text.hasPrefix("未读") || text.hasPrefix("标记") else { return nil }
            return spot.y
        }
        let listTop = listTops.min()
        let peers = rows.compactMap { text, spot -> PhoneTextSpot? in
            guard text == "豆包工作" || text == "维拉工时" else { return nil }
            guard spot.width <= 140 else { return nil }
            if let listTop, spot.y >= listTop { return nil }
            return spot
        }
        var chosen: PhoneTextSpot?
        for (text, spot) in rows {
            guard text == "假勤", spot.width <= 140 else { continue }
            if let listTop, spot.y >= listTop { continue }
            if listTop == nil, !peers.contains(where: { abs(spot.y - $0.y) <= 28 }) { continue }
            if chosen == nil || spot.y < (chosen?.y ?? .greatestFiniteMagnitude) { chosen = spot }
        }
        guard let chosen else { return nil }
        return (chosen.x + chosen.width / 2, chosen.y - 30)
    }

    private static func recognize(_ url: URL, viewportWidth: Double, viewportHeight: Double) -> [PhoneTextSpot] {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(viewportWidth)|\(viewportHeight)"
        cache.lock.lock()
        if let cached = cache.spots[key] {
            cache.lock.unlock()
            return cached
        }
        cache.lock.unlock()
        let spots = read(url, viewportWidth: viewportWidth, viewportHeight: viewportHeight)
        cache.lock.lock()
        cache.spots[key] = spots
        cache.lock.unlock()
        return spots
    }

    private static func read(_ url: URL, viewportWidth: Double, viewportHeight: Double) -> [PhoneTextSpot] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image)
        guard (try? handler.perform([request])) != nil else { return [] }
        let width = Double(image.width)
        let height = Double(image.height)
        guard width > 0, height > 0 else { return [] }
        let viewWidth = viewportWidth > 0 ? viewportWidth : 393
        let viewHeight = viewportHeight > 0 ? viewportHeight : viewWidth * height / width
        let scaleX = width / viewWidth
        let scaleY = height / viewHeight
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return PhoneTextSpot(
                text: text,
                x: box.origin.x * width / scaleX,
                y: (1 - box.origin.y - box.height) * height / scaleY,
                width: box.width * width / scaleX,
                height: box.height * height / scaleY
            )
        }
    }

    private static func compact(_ text: String) -> String {
        text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.map(String.init).joined()
    }
}
