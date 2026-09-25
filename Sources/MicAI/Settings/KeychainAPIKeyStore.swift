import Foundation
import Security

/// The OpenAI API key, kept in the login Keychain and nowhere else.
///
/// Not UserDefaults and not a file: both are plain text on disk and end up in
/// backups. The Keychain encrypts the value and ties it to this app. The key is
/// read on each request rather than cached, so removing it in Settings takes
/// effect immediately.
enum KeychainAPIKeyStore {
  private static let service = "MicAI.OpenAIAPIKey"
  private static let account = "default"

  private static var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read() -> String? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static var hasKey: Bool {
    read()?.isEmpty == false
  }

  @discardableResult
  static func save(_ key: String) -> Bool {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return delete()
    }
    let data = Data(trimmed.utf8)
    let update: [String: Any] = [kSecValueData as String: data]
    let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var add = baseQuery
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    return status == errSecSuccess
  }

  @discardableResult
  static func delete() -> Bool {
    let status = SecItemDelete(baseQuery as CFDictionary)
    return status == errSecSuccess || status == errSecItemNotFound
  }
}
