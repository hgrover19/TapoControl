import Foundation
import Security

/// Stores the derived KLAP auth hashes (never the password).
///
/// Uses the login keychain. If the keychain call is refused, it falls back to a 0600
/// file in the app's sandbox container, which no other app can read. Settings shows
/// which one is in use.
enum CredentialStore {
    enum Location: String { case keychain = "Keychain", file = "App container file", missing = "Not saved" }

    private static let account = "klap-auth"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConstants.keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TapoControl", isDirectory: true)
            .appendingPathComponent("klap-auth.json")
    }

    static func load() -> KlapAuth? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let auth = try? JSONDecoder().decode(KlapAuth.self, from: data) {
            return auth
        }
        if let url = fileURL, let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(KlapAuth.self, from: data)
        }
        return nil
    }

    @discardableResult
    static func save(_ auth: KlapAuth) throws -> Location {
        let data = try JSONEncoder().encode(auth)
        clear()
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "TapoControl bulb key"
        if SecItemAdd(add as CFDictionary, nil) == errSecSuccess {
            return .keychain
        }
        guard let url = fileURL else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return .file
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
    }

    static var location: Location {
        if SecItemCopyMatching(baseQuery as CFDictionary, nil) == errSecSuccess { return .keychain }
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) { return .file }
        return .missing
    }
}
