import Foundation

/// 用户看到的名字。工程目标、包名和 `~/Library/Application Support/MacBJ` 仍叫 MacBJ。
nonisolated enum ProductName {
    static var title: String { L("泊位") }
}

/// 侧边栏中的一种运行时。
/// 再加一种时：在这里增加 case，并新增一个 RuntimeProvider，注册到 ProviderRegistry。
nonisolated enum RuntimeKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case node
    case python
    case go
    case java
    case rust

    var id: Self { self }

    var title: String {
        switch self {
        case .node: "Node.js"
        case .python: "Python"
        case .go: "Go"
        case .java: "Java"
        case .rust: "Rust"
        }
    }

    var monogram: String {
        switch self {
        case .node: "JS"
        case .python: "Py"
        case .go: "Go"
        case .java: "Jv"
        case .rust: "Rs"
        }
    }

    var emptyTitle: String {
        switch self {
        case .node: L("没有找到 Node 版本管理器")
        case .python: L("没有找到 Python 版本管理器")
        case .go: L("没有读到 Go 版本")
        case .java: L("没有读到 Java 版本")
        case .rust: L("没有读到 Rust 版本")
        }
    }

    var emptyDetail: String {
        switch self {
        case .node: L("支持 fnm、nvm 和 Volta。安装其中任意一个，然后刷新。")
        case .python: L("支持 pyenv 和 uv。安装其中任意一个，然后刷新。")
        case .go: L("从 go.dev 下载官方版本，然后可以设为全局默认或写入项目。")
        case .java: L("从 Eclipse Temurin 下载官方版本，然后可以设为全局默认或写入项目。")
        case .rust: L("从 rust-lang.org 下载官方版本，然后可以设为全局默认或写入项目。")
        }
    }

    var usesOfficialArchive: Bool {
        switch self {
        case .go, .java, .rust: true
        case .node, .python: false
        }
    }
}

nonisolated enum RuntimeBackend: String, Equatable, Hashable, Sendable {
    case fnm
    case nvm
    case volta
    case pyenv
    case uv
    case official
    case missing

    init(marker: String) {
        switch marker.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "fnm": self = .fnm
        case "nvm": self = .nvm
        case "volta": self = .volta
        case "pyenv": self = .pyenv
        case "uv": self = .uv
        case "official": self = .official
        default: self = .missing
        }
    }

    var title: String {
        switch self {
        case .fnm: "fnm"
        case .nvm: "nvm"
        case .volta: "Volta"
        case .pyenv: "pyenv"
        case .uv: "uv"
        case .official: ProductName.title
        case .missing: L("系统")
        }
    }

    var canSwitch: Bool {
        self != .missing
    }

    /// 告诉用户这次切换实际改的是什么。
    var footnote: String {
        switch self {
        case .fnm:
            L("切换会执行 fnm default。新开的终端会使用这个版本，已经打开的终端不会变。")
        case .nvm:
            L("切换会修改 nvm 的 default 别名。新开的终端会使用这个版本，已经打开的终端不会变。")
        case .volta:
            L("切换会把 Volta 的默认 Node 设为所选版本。")
        case .pyenv:
            L("切换会执行 pyenv global。新开的终端会使用这个版本，已经打开的终端不会变。")
        case .uv:
            L("切换会执行 uv python pin --global。改的是 uv 的全局 Python，不会替换终端里 Homebrew 或系统自带的 python3。")
        case .official:
            L("全局默认记在%@里。更新终端钩子后，新开的终端会优先用它，不会卸掉系统里原来的工具链。", ProductName.title)
        case .missing:
            L("现在只能看到系统直接提供的版本。安装上面说的版本管理器之后，才能在这里切换。")
        }
    }
}
