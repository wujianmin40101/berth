import Foundation
import Testing
@testable import MacBJ

struct LanguageTests {
    @Test("english copy names the product and the language control")
    func englishCopyNamesTheProductAndTheLanguageControl() {
        #expect(EnglishCopy.table["泊位"] == "Berth")
        #expect(EnglishCopy.table["语言"] == "Language")
        #expect(EnglishCopy.table["跟随系统"] == "System")
        #expect(EnglishCopy.table["端口"] == "Ports")
    }

    @Test("an unset preference follows the mac language")
    func anUnsetPreferenceFollowsTheMacLanguage() {
        let previous = UserDefaults.standard.string(forKey: LanguagePreference.key)
        UserDefaults.standard.removeObject(forKey: LanguagePreference.key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: LanguagePreference.key)
            }
        }
        let saved = LanguageChoice.saved
        #expect(saved == .system)
        let preferred = Locale.preferredLanguages.first ?? ""
        if preferred.hasPrefix("en") {
            #expect(saved.resolved == .english)
        } else if preferred.hasPrefix("zh") {
            #expect(saved.resolved == .chinese)
        }
    }
}
