import CoreGraphics
import Foundation

// Lucide Sun → Moon，形变计划来自 morphicons 2.0.2。t = 0 是太阳，t = 1 是月亮。
enum SunMoonPlan {
    static let count = 9
    static let samples = 64
    static let payload = "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"

    static let shared: MorphPlan = {
        let data = Data(base64Encoded: payload) ?? Data()
        let floats = data.withUnsafeBytes { raw -> [CGFloat] in
            let values = raw.bindMemory(to: Float.self)
            return values.map { CGFloat($0) }
        }
        var cursor = 0
        func take(_ n: Int) -> [CGFloat] {
            let slice = Array(floats[cursor..<(cursor + n)])
            cursor += n
            return slice
        }
        func one() -> CGFloat {
            let value = floats[cursor]
            cursor += 1
            return value
        }
        let pair = samples * 2
        var items: [MorphItem] = []
        items.reserveCapacity(count)
        for _ in 0..<count {
            let aC = take(pair)
            let bT = take(pair)
            let caX = one(), caY = one(), cbX = one(), cbY = one()
            let theta = one(), lnSigma = one()
            let closed = one() > 0.5
            let hasBlock = one() > 0.5
            let offX = one(), offY = one(), driftX = one(), driftY = one()
            items.append(MorphItem(
                aC: aC, bT: bT,
                caX: caX, caY: caY, cbX: cbX, cbY: cbY,
                theta: theta, lnSigma: lnSigma, closed: closed,
                block: hasBlock ? MorphBlock(offX: offX, offY: offY, driftX: driftX, driftY: driftY) : nil
            ))
        }
        return MorphPlan(n: samples, items: items)
    }()
}

struct MorphBlock {
    var offX: CGFloat
    var offY: CGFloat
    var driftX: CGFloat
    var driftY: CGFloat
}

struct MorphItem {
    var aC: [CGFloat]
    var bT: [CGFloat]
    var caX: CGFloat
    var caY: CGFloat
    var cbX: CGFloat
    var cbY: CGFloat
    var theta: CGFloat
    var lnSigma: CGFloat
    var closed: Bool
    var block: MorphBlock?
}

struct MorphPlan {
    var n: Int
    var items: [MorphItem]

    func path(at t: CGFloat, in size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let sx = size.width / 24
        let sy = size.height / 24
        for item in items {
            let scale = exp(item.lnSigma * t)
            let angle = item.theta * t
            let cosA = cos(angle) * scale
            let sinA = sin(angle) * scale
            let cx: CGFloat
            let cy: CGFloat
            if let block = item.block {
                cx = item.caX + block.driftX * t + (block.offX * cosA - block.offY * sinA - block.offX)
                cy = item.caY + block.driftY * t + (block.offX * sinA + block.offY * cosA - block.offY)
            } else {
                cx = item.caX + (item.cbX - item.caX) * t
                cy = item.caY + (item.cbY - item.caY) * t
            }
            for i in 0..<n {
                let px = item.aC[2 * i] + (item.bT[2 * i] - item.aC[2 * i]) * t
                let py = item.aC[2 * i + 1] + (item.bT[2 * i + 1] - item.aC[2 * i + 1]) * t
                let point = CGPoint(x: (cx + px * cosA - py * sinA) * sx, y: (cy + px * sinA + py * cosA) * sy)
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            if item.closed { path.closeSubpath() }
        }
        return path
    }
}
