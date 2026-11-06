import Foundation

nonisolated struct RuntimeVersion: Identifiable, Hashable, Sendable {
    var name: String
    var isCurrent: Bool
    var isInstalled: Bool = true
    var channel: ReleaseChannel = .unknown
    var releasedOn: String? = nil
    var npm: String? = nil
    var v8: String? = nil

    var id: String { name }

    /// 列表上显示的版本号。去掉 Node 常见的前缀 v。
    var title: String {
        guard name.hasPrefix("v"), name.dropFirst().first?.isNumber == true else {
            return name
        }
        return String(name.dropFirst())
    }
}

nonisolated struct RuntimeSnapshot: Equatable, Sendable {
    var kind: RuntimeKind
    var backend: RuntimeBackend
    var versions: [RuntimeVersion]
    var loadError: String?
    var remoteFailed: Bool = false

    var canSwitch: Bool {
        backend.canSwitch && loadError == nil
    }

    var installed: [RuntimeVersion] {
        versions.filter(\.isInstalled)
    }

    var available: [RuntimeVersion] {
        versions.filter { !$0.isInstalled }
    }
}
