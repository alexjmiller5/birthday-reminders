import BirthdaysCore
import Foundation
import Security

struct Connection: Codable {
  var endpoint: String
  var token: String
  var source: PeopleSource
  var enrollmentProfile: EnrollmentProfileReceipt? = nil
}

struct ConnectionStore {
  let service: String
  init(service: String = Bundle.main.bundleIdentifier! + ".connection") { self.service = service }
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service, kSecAttrAccount as String: "life-data",
    ]
  }
  func load() throws -> Connection? {
    var query = query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainError(status: status)
    }
    return try JSONDecoder().decode(Connection.self, from: data)
  }
  func save(_ connection: Connection) throws {
    let data = try JSONEncoder().encode(connection)
    let attributes: [String: Any] = [
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }
  func clear() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }
}

struct KeychainError: LocalizedError {
  let status: OSStatus
  var errorDescription: String? {
    "Secure storage is unavailable (\(status)). Unlock your phone and try again."
  }
}
