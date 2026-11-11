import Foundation
import Observation

/// 界面语言。没选过时跟随这台 Mac 的首选语言；只有中文和英文两套文案。
nonisolated enum LanguageChoice: String, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    /// 分段上的名字。中文和 English 固定用各自的写法，避免切到另一种语言后找不到路回来。
    var segmentTitle: String {
        switch self {
        case .system: L("跟随系统")
        case .chinese: "中文"
        case .english: "English"
        }
    }

    var resolved: ResolvedLanguage {
        switch self {
        case .chinese: .chinese
        case .english: .english
        case .system: Self.systemResolved
        }
    }

    static var systemResolved: ResolvedLanguage {
        for language in Locale.preferredLanguages {
            if language.hasPrefix("zh") { return .chinese }
            if language.hasPrefix("en") { return .english }
        }
        return .chinese
    }

    static var saved: LanguageChoice {
        let raw = UserDefaults.standard.string(forKey: LanguagePreference.key) ?? ""
        return LanguageChoice(rawValue: raw) ?? .system
    }
}

nonisolated enum ResolvedLanguage: Equatable {
    case chinese
    case english
}

/// 后台线程和命令行也能读。界面切换时由 LanguageStore 写入。
nonisolated enum LanguagePreference {
    static let key = "macbj.language"
}

nonisolated enum AppLanguage {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: ResolvedLanguage?

    nonisolated(unsafe) static var current: ResolvedLanguage {
        get {
            lock.lock()
            defer { lock.unlock() }
            if let stored { return stored }
            let resolved = LanguageChoice.saved.resolved
            stored = resolved
            return resolved
        }
        set {
            lock.lock()
            stored = newValue
            lock.unlock()
        }
    }
}

@MainActor
@Observable
final class LanguageStore {
    static let shared = LanguageStore()

    var choice: LanguageChoice {
        didSet { persist() }
    }

    var locale: Locale {
        Locale(identifier: choice.resolved == .english ? "en" : "zh-Hans")
    }

    private init() {
        choice = LanguageChoice.saved
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(choice.rawValue, forKey: LanguagePreference.key)
        AppLanguage.current = choice.resolved
    }
}

nonisolated func L(_ source: String) -> String {
    guard AppLanguage.current == .english else { return source }
    return EnglishCopy.table[source] ?? source
}

nonisolated func L(_ source: String, _ args: CVarArg...) -> String {
    let template = L(source)
    return String(format: template, locale: Locale(identifier: AppLanguage.current == .english ? "en" : "zh_CN"), arguments: args)
}

nonisolated enum ShellLiteral {
    /// 放进 shell 单引号。英文里的撇号不会把命令截断。
    nonisolated static func singleQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
