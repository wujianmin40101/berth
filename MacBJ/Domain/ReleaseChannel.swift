import Foundation

nonisolated enum ReleaseChannel: String, Equatable, Hashable, Sendable {
    case lts
    case stable
    case deprecated
    case unknown

    var title: String {
        switch self {
        case .lts: "LTS"
        case .stable: L("稳定")
        case .deprecated: L("已弃用")
        case .unknown: ""
        }
    }
}

nonisolated enum VersionOrder {
    static func key(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("v"), trimmed.dropFirst().first?.isNumber == true else {
            return trimmed
        }
        return String(trimmed.dropFirst())
    }

    static func parts(_ name: String) -> [Int] {
        let pieces = key(name).split(separator: "+", maxSplits: 1)
        var numbers = pieces[0].split(separator: ".").prefix(3).compactMap { Int($0) }
        if pieces.count > 1, let build = Int(pieces[1]) {
            numbers.append(build)
        }
        return numbers
    }

    static func major(_ name: String) -> Int? {
        parts(name).first
    }

    static func minorKey(_ name: String) -> String? {
        let numbers = parts(name)
        guard numbers.count >= 2 else { return nil }
        return "\(numbers[0]).\(numbers[1])"
    }

    /// 按版本号从新到旧。无法解析的名字排在后面。
    static func isNewer(_ lhs: String, than rhs: String) -> Bool {
        isNewer(parts(lhs), than: parts(rhs))
    }

    static func isNewer(_ left: [Int], than right: [Int]) -> Bool {
        if left.isEmpty { return false }
        if right.isEmpty { return true }
        for index in 0..<max(left.count, right.count) {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue != rightValue { return leftValue > rightValue }
        }
        return false
    }
}
