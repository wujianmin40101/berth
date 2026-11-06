import Foundation
import Security

enum SecretStore {
    private static let service = "app.macbj.desktop.env"

    static func names() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let rows = result as? [[String: Any]] else { return [] }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func value(named name: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    static func save(name: String, value: String) -> String? {
        if let problem = EnvName.problem(in: name) { return problem }
        guard ShellQuote.isSingleLine(value) else { return "变量值不能包含换行。" }
        let base = query(name)
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        return status == errSecSuccess ? nil : "钥匙串没有保存。"
    }

    static func remove(name: String) {
        SecItemDelete(query(name) as CFDictionary)
    }

    static func environment() -> [String: String] {
        names().reduce(into: [:]) { result, name in
            if let value = value(named: name) {
                result[name] = value
            }
        }
    }

    private static func query(_ name: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]
    }
}
