import Foundation
import Security

/// Stockage de secrets dans le trousseau (clés d'API). Rien n'est écrit dans la base ni dans UserDefaults.
enum KeychainStore {
    private static let service = "iFinance.quoteProviders"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Enregistre la valeur ; une valeur vide ou nil supprime l'entrée
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return true }
        var attributes = base
        attributes[kSecValueData as String] = data
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
