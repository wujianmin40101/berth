import Foundation

nonisolated struct VolumeSpace: Equatable, Sendable {
    var name: String
    var total: UInt64
    var available: UInt64

    var used: UInt64 { total > available ? total - available : 0 }
}

nonisolated struct DiskNode: Equatable, Identifiable, Sendable {
    var name: String
    var path: String
    var bytes: UInt64
    var partial: Bool
    var pending: Bool = false
    var children: [DiskNode]
    var id: String { path }

    var canEnter: Bool {
        name != "其他" && children.contains { $0.name != "其他" && $0.bytes > 0 }
    }
}

nonisolated struct TreemapInput: Equatable, Sendable {
    var id: String
    var title: String
    var value: Double
}

nonisolated struct TreemapTile: Equatable, Sendable, Identifiable {
    var id: String
    var title: String
    var value: Double
    var rect: CGRect
}

nonisolated enum TreemapLayout {
    static func tiles(_ items: [TreemapInput], in rect: CGRect) -> [TreemapTile] {
        let sorted = items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        let total = sorted.reduce(0) { $0 + $1.value }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }
        let scale = rect.width * rect.height / total
        let weighted = sorted.map { (item: $0, area: $0.value * scale) }
        var output: [TreemapTile] = []
        place(weighted, row: [], in: rect, into: &output)
        return output
    }

    private static func place(
        _ items: [(item: TreemapInput, area: Double)],
        row: [(item: TreemapInput, area: Double)],
        in rect: CGRect,
        into output: inout [TreemapTile]
    ) {
        guard let next = items.first else {
            layout(row, in: rect, into: &output)
            return
        }
        let side = min(rect.width, rect.height)
        let trial = row + [next]
        if row.isEmpty || worst(row, side: side) >= worst(trial, side: side) {
            place(Array(items.dropFirst()), row: trial, in: rect, into: &output)
        } else {
            let remaining = layout(row, in: rect, into: &output)
            place(items, row: [], in: remaining, into: &output)
        }
    }

    private static func worst(_ row: [(item: TreemapInput, area: Double)], side: CGFloat) -> Double {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0, side > 0 else { return .greatestFiniteMagnitude }
        let maxArea = row.map(\.area).max() ?? 0
        let minArea = row.map(\.area).min() ?? 0
        let side2 = Double(side * side)
        return max((side2 * maxArea) / (sum * sum), (sum * sum) / (side2 * minArea))
    }

    @discardableResult
    private static func layout(
        _ row: [(item: TreemapInput, area: Double)],
        in rect: CGRect,
        into output: inout [TreemapTile]
    ) -> CGRect {
        let sum = row.reduce(0) { $0 + $1.area }
        guard sum > 0, !row.isEmpty else { return rect }
        if rect.width < rect.height {
            let width = sum / rect.height
            var y = rect.minY
            for entry in row {
                let height = entry.area / width
                output.append(TreemapTile(id: entry.item.id, title: entry.item.title, value: entry.item.value, rect: CGRect(x: rect.minX, y: y, width: width, height: height)))
                y += height
            }
            return CGRect(x: rect.minX + width, y: rect.minY, width: max(0, rect.width - width), height: rect.height)
        }
        let height = sum / rect.width
        var x = rect.minX
        for entry in row {
            let width = entry.area / height
            output.append(TreemapTile(id: entry.item.id, title: entry.item.title, value: entry.item.value, rect: CGRect(x: x, y: rect.minY, width: width, height: height)))
            x += width
        }
        return CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: max(0, rect.height - height))
    }
}

nonisolated enum DiskMap {
    /// 先量用户、应用程序和系统，这三项决定整张图的形状。
    static let rootNames = ["Users", "Applications", "System", "Library", "private", "opt", "usr"]

    static func hasFullDiskAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    static func volume() -> VolumeSpace {
        let url = URL(fileURLWithPath: "/System/Volumes/Data")
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let total = UInt64(values?.volumeTotalCapacity ?? 0)
        var available: UInt64 = 0
        if let important = values?.volumeAvailableCapacityForImportantUsage {
            available = UInt64(important)
        } else if let regular = values?.volumeAvailableCapacity {
            available = UInt64(regular)
        }
        let name = values?.volumeName ?? "启动磁盘"
        return VolumeSpace(name: name, total: total, available: available)
    }

    static func measure(_ name: String, control: AllocatedSize.ScanControl? = nil) -> DiskNode {
        let path = "/\(name)"
        let scan = AllocatedSize.tree(path, deadline: Date().addingTimeInterval(45), control: control)
        var node = diskNode(scan, title: name)
        if !scan.complete || (!hasFullDiskAccess() && (name == "Users" || name == "Library")) {
            node.partial = true
        }
        return node
    }

    private static func diskNode(_ entry: AllocatedSize.Entry, title: String? = nil) -> DiskNode {
        let name: String
        if let title {
            name = title
        } else if entry.name == "其他" {
            name = entry.name
        } else if entry.path.hasSuffix(".app") {
            name = URL(fileURLWithPath: entry.path).deletingPathExtension().lastPathComponent
        } else {
            name = entry.name
        }
        return DiskNode(
            name: name,
            path: entry.path,
            bytes: entry.bytes,
            partial: !entry.complete,
            children: entry.children.map { diskNode($0) }
        )
    }
}
