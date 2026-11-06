import Foundation

enum MirrorSettings {
    static func choice(for kind: RuntimeKind) -> MirrorChoice {
        let raw = UserDefaults.standard.string(forKey: key(kind)) ?? ""
        return MirrorChoice(rawValue: raw) ?? .official
    }

    static func set(_ choice: MirrorChoice, for kind: RuntimeKind) {
        UserDefaults.standard.set(choice.rawValue, forKey: key(kind))
    }

    private static func key(_ kind: RuntimeKind) -> String {
        "macbj.mirror.\(kind.rawValue)"
    }
}

nonisolated enum MirrorChoice: String, Equatable, Hashable, Sendable, CaseIterable, Identifiable {
    case official
    case china

    var id: String { rawValue }

    var title: String {
        switch self {
        case .official: L("官方")
        case .china: L("国内")
        }
    }
}

nonisolated struct ProjectPin: Equatable, Sendable {
    var fileName: String
    var version: String
    /// pyproject.toml 的 requires-python 只展示，不写回。
    var writable: Bool
}

nonisolated struct VersionAlias: Identifiable, Hashable, Sendable {
    var name: String
    var version: String

    var id: String { name }
}

nonisolated enum HookStatus: Equatable, Sendable {
    case missing
    case installed
    case outdated

    var title: String {
        switch self {
        case .missing: L("启用目录切换")
        case .installed: L("目录切换已启用")
        case .outdated: L("更新目录切换")
        }
    }
}
