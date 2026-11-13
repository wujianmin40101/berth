import Foundation

/// 外壳样式跟 iPhone Use 的 `appearanceForModel` 同一份名单。没有确认过的机型名就不用灵动岛。
nonisolated enum PhoneShellKind: String, Equatable, Sendable {
    case plain
    case rounded
    case island
}

nonisolated enum PhoneStageLive: String, Equatable, Sendable {
    case connecting
    case paused
    case cached
    case offline
}

nonisolated struct PhoneGestureMark: Equatable, Sendable, Identifiable {
    var id: Int
    var kind: String
    var x: Double
    var y: Double
    var x2: Double
    var y2: Double
    var at: Int
    var viewWidth: Double
    var viewHeight: Double

    var isDrag: Bool { kind == "drag" }
}

nonisolated struct PhoneShot: Equatable, Sendable, Identifiable {
    var url: URL
    var name: String
    var stamp: String
    var crop: Bool

    var id: String { url.path }
}

/// 打卡日志里的一步。画面状态只留预览的最近一次点击，进入假勤和切换账户在这里。
nonisolated struct PhoneTraceStep: Equatable, Sendable, Identifiable {
    var id: String
    var kind: String
    var detail: String
    var x: Double?
    var y: Double?
    var at: Date
    var shot: URL?
}

nonisolated struct PhoneJobRecord: Equatable, Sendable, Identifiable {
    var id: String
    var action: String
    var state: String
    var phase: String
    var error: String
    var created: String
}

/// 从 iPhone Use 的状态目录读出画面、手势、恢复和截图。不读取签名、令牌或设备标识。
nonisolated struct PhoneStageSnapshot: Equatable, Sendable {
    var live: PhoneStageLive
    var paused: Bool
    var pauseReason: String
    var sessionOpen: Bool
    var endpoint: String
    var port: Int
    var bundleID: String
    var sourceDirectory: String
    var model: String
    var shell: PhoneShellKind
    var operating: Bool
    var viewportWidth: Double
    var viewportHeight: Double
    /// 仍在 10 秒内的手势，画面上才画光标。
    var gestures: [PhoneGestureMark]
    /// 文件里留下的手势，过期也保留给手势页。
    var recorded: [PhoneGestureMark]
    var steps: [PhoneTraceStep]
    var pages: [PhoneShot]
    var crops: [PhoneShot]
    var droppedTwins: Int
    var jobs: [PhoneJobRecord]
    var recoveryPhase: String
    var startState: String

    static let empty = PhoneStageSnapshot(
        live: .offline, paused: false, pauseReason: "", sessionOpen: false, endpoint: "",
        port: 0, bundleID: "", sourceDirectory: "", model: "", shell: .plain, operating: false,
        viewportWidth: 0, viewportHeight: 0, gestures: [], recorded: [], steps: [], pages: [], crops: [], droppedTwins: 0,
        jobs: [], recoveryPhase: "", startState: ""
    )

    var exposed: String {
        [
            live.rawValue, pauseReason, endpoint, bundleID, sourceDirectory, model, shell.rawValue,
            recoveryPhase, startState,
            gestures.map(\.kind).joined(separator: ","),
            recorded.map(\.kind).joined(separator: ","),
            steps.map(\.kind).joined(separator: ","),
            pages.map(\.name).joined(separator: ","),
            crops.map(\.name).joined(separator: ","),
            jobs.map { "\($0.action) \($0.state) \($0.phase) \($0.error)" }.joined(separator: "\n"),
        ].joined(separator: "\n")
    }
}

nonisolated enum PhoneStage {
    private static let islandModels: Set<String> = [
        "iphone 14 pro", "iphone 14 pro max",
        "iphone 15", "iphone 15 plus", "iphone 15 pro", "iphone 15 pro max",
        "iphone 16", "iphone 16 plus", "iphone 16 pro", "iphone 16 pro max",
        "iphone 17", "iphone 17 pro", "iphone 17 pro max", "iphone air",
        "iphone 18 pro", "iphone 18 pro max",
    ]
    private static let roundedModels: Set<String> = [
        "iphone x", "iphone xr", "iphone xs", "iphone xs max",
        "iphone 11", "iphone 11 pro", "iphone 11 pro max",
        "iphone 12", "iphone 12 mini", "iphone 12 pro", "iphone 12 pro max",
        "iphone 13", "iphone 13 mini", "iphone 13 pro", "iphone 13 pro max",
        "iphone 14", "iphone 14 plus", "iphone 16e", "iphone 17e",
    ]
    private static let eventAge: Double = 10_000
    private static let busyAge: Double = 650

    static func shell(for model: String) -> PhoneShellKind {
        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .lowercased()
        if islandModels.contains(name) { return .island }
        if roundedModels.contains(name) { return .rounded }
        return .plain
    }

    static func load(directory: URL, now: Date = Date()) -> PhoneStageSnapshot {
        let screen = object(directory.appendingPathComponent("screen-state.json"))
        let config = object(directory.appendingPathComponent("config.json"))
        let session = object(directory.appendingPathComponent("session.json"))
        let paused = screen["paused"] as? Bool == true
        var reason = ""
        if paused {
            let raw = text(screen["pause_reason"])
            reason = (raw == "device_locked" || raw == "authentication") ? raw : "unknown"
        }
        let port = number(config["local_port"]).map { Int($0) } ?? 0
        let bundle = text(config["bundle_id"])
        let source = text(config["source_dir"])
        let sourceKept = source.hasPrefix(directory.path) ? source : ""
        let sessionID = text(session["session_id"])
        let sessionOpen = !sessionID.isEmpty
        let endpoint = localEndpoint(text(session["url"]), port: port)
        let model = text(screen["model"])
        let viewport = point(screen["viewport"])
        let nowMS = now.timeIntervalSince1970 * 1000
        let recorded = marks(screen["events"])
        let gestures = recorded.filter { nowMS - Double($0.at) < eventAge }
        let finished = number(screen["finished_at"]) ?? 0
        let actors = screen["actors"] as? [String: Any] ?? [:]
        let operating = !paused && (!actors.isEmpty || (finished > 0 && nowMS - finished < busyAge))
        let jobs = readJobs(directory.appendingPathComponent("jobs", isDirectory: true))
        let shots = readShots(directory.appendingPathComponent("artifacts", isDirectory: true))
        let log = (try? String(contentsOf: directory.appendingPathComponent("logs/punch.log"), encoding: .utf8)) ?? ""
        let pinned = PhoneScreenText.pinnedAttendance(
            in: shots.pages,
            viewportWidth: viewport?.x ?? 0,
            viewportHeight: viewport?.y ?? 0
        )
        let steps = traces(log: log, shots: shots.pages, pinned: pinned)
        let recover = jobs.first { $0.action == "recover" && ($0.state == "running" || $0.state == "queued") }
        let start = jobs.first { $0.action == "start" }
        let startState = start?.state ?? ""
        let live: PhoneStageLive
        if paused {
            live = .paused
        } else if shots.pages.isEmpty {
            live = (sessionOpen || startState == "running" || startState == "queued") ? .connecting : .offline
        } else {
            live = .cached
        }
        return PhoneStageSnapshot(
            live: live,
            paused: paused,
            pauseReason: reason,
            sessionOpen: sessionOpen,
            endpoint: endpoint,
            port: port,
            bundleID: bundle,
            sourceDirectory: sourceKept,
            model: model,
            shell: shell(for: model),
            operating: operating,
            viewportWidth: viewport?.x ?? 0,
            viewportHeight: viewport?.y ?? 0,
            gestures: gestures,
            recorded: recorded,
            steps: steps,
            pages: shots.pages,
            crops: shots.crops,
            droppedTwins: shots.dropped,
            jobs: jobs,
            recoveryPhase: recover?.phase ?? "",
            startState: startState
        )
    }

    static func traces(log: String, shots: [PhoneShot], pinned: (url: URL, x: Double, y: Double)? = nil) -> [PhoneTraceStep] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var steps: [PhoneTraceStep] = []
        for rawLine in log.split(separator: "\n", omittingEmptySubsequences: false).suffix(2000) {
            let line = String(rawLine)
            guard line.count >= 20, line.dropFirst(19).first == " " else { continue }
            let stamp = String(line.prefix(19))
            guard let date = formatter.date(from: stamp) else { continue }
            let message = String(line.dropFirst(20))
            guard let step = trace(message, at: date, index: steps.count, shots: shots, pinned: pinned) else { continue }
            steps.append(step)
        }
        if steps.count > 40 { steps = Array(steps.suffix(40)) }
        return steps
    }

    private static func trace(_ message: String, at date: Date, index: Int, shots: [PhoneShot], pinned: (url: URL, x: Double, y: Double)?) -> PhoneTraceStep? {
        let id = "\(index)-\(date.timeIntervalSince1970)"
        if message.hasPrefix("opened "), let spot = trailingPoint(message) {
            let x = pinned?.x ?? spot.x
            let y = pinned?.y ?? spot.y
            let image = pinned?.url ?? shot(for: message, at: date, shots: shots)
            return PhoneTraceStep(id: id, kind: "open", detail: "假勤", x: x, y: y, at: date, shot: image)
        }
        if message.hasPrefix("tapped "), let spot = trailingPoint(message) {
            let detail = message.dropFirst(7).split(separator: " ").first.map(String.init) ?? ""
            return PhoneTraceStep(id: id, kind: "tap", detail: detail, x: spot.x, y: spot.y, at: date, shot: shot(for: message, at: date, shots: shots))
        }
        if message.hasPrefix("switch ") {
            return PhoneTraceStep(id: id, kind: "switch", detail: String(message.dropFirst(7)), x: nil, y: nil, at: date, shot: shot(for: message, at: date, shots: shots))
        }
        if message.hasPrefix("ocr ") {
            let name = String(message.dropFirst(4))
            guard !name.isEmpty, !name.hasPrefix("failed") else { return nil }
            return PhoneTraceStep(id: id, kind: "recognize", detail: name, x: nil, y: nil, at: date, shot: shot(for: message, at: date, shots: shots))
        }
        if message.hasPrefix("page "), message != "page not-ready" {
            return PhoneTraceStep(id: id, kind: "page", detail: String(message.dropFirst(5)), x: nil, y: nil, at: date, shot: shot(for: message, at: date, shots: shots))
        }
        if message.hasPrefix("上班 ") || message.hasPrefix("下班 ") {
            let name = String(message.dropFirst(3))
            guard !name.isEmpty else { return nil }
            return PhoneTraceStep(id: id, kind: "account", detail: name, x: nil, y: nil, at: date, shot: shot(for: message, at: date, shots: shots))
        }
        return nil
    }

    private static func trailingPoint(_ message: String) -> (x: Double, y: Double)? {
        guard let open = message.lastIndex(of: "("), let close = message.lastIndex(of: ")"), open < close else { return nil }
        let body = message[message.index(after: open)..<close]
        let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else { return nil }
        return (x, y)
    }

    private static func shot(for message: String, at date: Date, shots: [PhoneShot]) -> URL? {
        if let token = message.split(separator: " ").last, token.contains("artifacts/") {
            let stem = URL(fileURLWithPath: String(token)).deletingPathExtension().lastPathComponent
            if let match = shots.first(where: { $0.url.deletingPathExtension().lastPathComponent == stem }) {
                return match.url
            }
        }
        let dated = shots.compactMap { shot -> (URL, TimeInterval)? in
            guard let at = artifactDate(shot.name) else { return nil }
            return (shot.url, abs(at.timeIntervalSince(date)))
        }
        guard let nearest = dated.min(by: { $0.1 < $1.1 }), nearest.1 <= 90 else { return nil }
        return nearest.0
    }

    static func artifactDate(_ name: String) -> Date? {
        guard name.count >= 15 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.date(from: String(name.prefix(15)))
    }

    private static func localEndpoint(_ raw: String, port: Int) -> String {
        guard let url = URL(string: raw), let host = url.host?.lowercased(), host == "127.0.0.1" || host == "localhost" else {
            return ""
        }
        let value = url.port ?? port
        return value > 0 ? "\(host):\(value)" : host
    }

    private static func readJobs(_ directory: URL) -> [PhoneJobRecord] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.compactMap { url in
            let json = object(url)
            let id = text(json["id"])
            let action = text(json["action"])
            guard !id.isEmpty, !action.isEmpty else { return nil }
            return PhoneJobRecord(
                id: id,
                action: action,
                state: text(json["state"]),
                phase: text(json["recovery_phase"]),
                error: text(json["error"]),
                created: text(json["created_at"])
            )
        }
        .sorted { $0.created > $1.created }
    }

    private static func readShots(_ directory: URL) -> (pages: [PhoneShot], crops: [PhoneShot], dropped: Int) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let images = urls.filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        var grouped: [String: [URL]] = [:]
        for url in images {
            grouped[url.deletingPathExtension().lastPathComponent, default: []].append(url)
        }
        var pages: [PhoneShot] = []
        var crops: [PhoneShot] = []
        var dropped = 0
        for (name, group) in grouped {
            let png = group.first { $0.pathExtension.lowercased() == "png" }
            let kept = png ?? group[0]
            dropped += group.count - 1
            let shot = PhoneShot(url: kept, name: kept.lastPathComponent, stamp: stamp(name), crop: !name.hasPrefix("20"))
            if shot.crop { crops.append(shot) } else { pages.append(shot) }
        }
        pages.sort { $0.name > $1.name }
        crops.sort { $0.name < $1.name }
        if pages.count > 12 { pages = Array(pages.prefix(12)) }
        return (pages, crops, dropped)
    }

    private static func stamp(_ name: String) -> String {
        guard name.count >= 15, name.dropFirst(8).first == "T" else { return name }
        let hour = name.dropFirst(9).prefix(2)
        let minute = name.dropFirst(11).prefix(2)
        let second = name.dropFirst(13).prefix(2)
        return "\(hour):\(minute):\(second)"
    }

    private static func marks(_ raw: Any?) -> [PhoneGestureMark] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let kind = text(row["kind"])
            guard let id = number(row["id"]).map({ Int($0) }), kind == "tap" || kind == "drag" else {
                return nil
            }
            let at = number(row["at"]) ?? 0
            guard at > 0 else { return nil }
            let view = point(row["viewport"])
            if kind == "tap", let spot = point(row["point"]) {
                return PhoneGestureMark(id: id, kind: kind, x: spot.x, y: spot.y, x2: spot.x, y2: spot.y, at: Int(at), viewWidth: view?.x ?? 0, viewHeight: view?.y ?? 0)
            }
            if kind == "drag", let from = point(row["from"]), let to = point(row["to"]) {
                return PhoneGestureMark(id: id, kind: kind, x: from.x, y: from.y, x2: to.x, y2: to.y, at: Int(at), viewWidth: view?.x ?? 0, viewHeight: view?.y ?? 0)
            }
            return nil
        }
        .sorted { $0.id < $1.id }
    }

    private static func object(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    private static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull), let text = value as? String else { return "" }
        return text
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Int { return Double(value) }
        if let value = value as? Double { return value }
        guard let value = value as? NSNumber else { return nil }
        if CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        return value.doubleValue
    }

    private static func point(_ value: Any?) -> (x: Double, y: Double)? {
        guard let row = value as? [String: Any] else { return nil }
        if let x = number(row["x"]), let y = number(row["y"]), x >= 0, y >= 0 { return (x, y) }
        if let width = number(row["width"]), let height = number(row["height"]), width > 0, height > 0 { return (width, height) }
        return nil
    }
}
