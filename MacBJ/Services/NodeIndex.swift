import Foundation

nonisolated struct NodeRelease: Equatable, Sendable {
    var version: String
    var channel: ReleaseChannel
    var major: Int
    var releasedOn: String?
    var npm: String?
    var v8: String?
}

nonisolated enum NodeIndex {
    static func parse(_ data: Data) -> [NodeRelease] {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [] }
        let accepted = rows.compactMap { row -> Candidate? in
            guard row.version.wholeMatch(of: /^v\d+\.\d+\.\d+$/) != nil,
                  let major = VersionOrder.major(row.version) else {
                return nil
            }
            return Candidate(
                version: row.version,
                major: major,
                isLTS: row.isLTS,
                releasedOn: row.date,
                npm: row.npm,
                v8: row.v8
            )
        }
        return classify(accepted)
    }

    /// index.json 的 `2026-10-21` 显示成 `Oct 21, 2026`。无法解析时返回破折号。
    static func displayDate(_ iso: String?) -> String {
        guard let iso else { return "—" }
        let parts = iso.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              (1...12).contains(month),
              let day = Int(parts[2]) else {
            return "—"
        }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[month - 1]) \(day), \(parts[0])"
    }

    /// 每个仍在维护的主版本只留最新补丁，供下载列表使用。
    static func offerings(_ releases: [NodeRelease]) -> [NodeRelease] {
        var best: [Int: NodeRelease] = [:]
        for release in releases where release.channel == .lts || release.channel == .stable {
            if let existing = best[release.major], !VersionOrder.isNewer(release.version, than: existing.version) {
                continue
            }
            best[release.major] = release
        }
        return best.values.sorted { VersionOrder.isNewer($0.version, than: $1.version) }
    }

    static func channel(of version: String, in releases: [NodeRelease]) -> ReleaseChannel {
        let key = VersionOrder.key(version)
        if let exact = releases.first(where: { VersionOrder.key($0.version) == key }) {
            return exact.channel
        }
        guard let major = VersionOrder.major(version) else { return .unknown }
        return releases.first { $0.major == major }?.channel ?? .unknown
    }

    static func fetch(_ mirror: MirrorChoice) async -> [NodeRelease]? {
        let address = switch mirror {
        case .official: "https://nodejs.org/dist/index.json"
        case .china: "https://npmmirror.com/mirrors/node/index.json"
        }
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("MacBJ", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return parse(data)
        } catch {
            return nil
        }
    }

    private struct Candidate {
        var version: String
        var major: Int
        var isLTS: Bool
        var releasedOn: String?
        var npm: String?
        var v8: String?
    }

    /// 最新三个 LTS 主版本仍算在维护（当前、Active、Maintenance）。比它们新的非 LTS 主版本是稳定版，更老的标为已弃用。
    private static func classify(_ accepted: [Candidate]) -> [NodeRelease] {
        let ltsMajors = Set(accepted.filter(\.isLTS).map(\.major))
        let activeLTS = Set(ltsMajors.sorted().suffix(3))
        let latestLTS = ltsMajors.max()
        let stableMajor = accepted
            .filter { !$0.isLTS && (latestLTS == nil || $0.major > latestLTS!) }
            .map(\.major)
            .max()

        return accepted.map { item in
            let channel: ReleaseChannel = if activeLTS.contains(item.major) {
                .lts
            } else if let stableMajor, item.major == stableMajor {
                .stable
            } else {
                .deprecated
            }
            return NodeRelease(
                version: item.version,
                channel: channel,
                major: item.major,
                releasedOn: item.releasedOn,
                npm: item.npm,
                v8: item.v8
            )
        }
    }

    private struct Row: Decodable {
        var version: String
        var lts: LTSField
        var date: String?
        var npm: String?
        var v8: String?

        var isLTS: Bool {
            if case .named = lts { return true }
            return false
        }
    }

    private enum LTSField: Decodable {
        case named(String)
        case none

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let name = try? container.decode(String.self) {
                self = name.isEmpty ? .none : .named(name)
                return
            }
            if let flag = try? container.decode(Bool.self) {
                self = flag ? .named("") : .none
                return
            }
            self = .none
        }
    }
}
