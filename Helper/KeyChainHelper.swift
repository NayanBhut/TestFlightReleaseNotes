//
//  CredentialStorage.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import Foundation
import Security

struct Credential: Codable {
    let key: String
    let issuerID: String
    let privateKey: String
    let keyID: String
}

final class CredentialStorage {
    static var shared: CredentialStorage = .init()

    /// Scopes every keychain item to this service so credentials from
    /// other services are never read, written, or listed.
    private static let service = "com.appstore.release-notes"
    private static let accountPrefix = "App_Store_Connect_API_"

    private init() {
        migrateLegacyUnscopedItems()
        if selectedTeam == nil {
            restoreDefaultTeam()
        }
    }

    /// One-time upgrade path: KeychainSwift stored items with no
    /// kSecAttrService, so pre-scoping teams are invisible to the
    /// service-scoped queries. Copy each legacy entry into a
    /// service-scoped item (keeping the scoped one when both exist),
    /// then remove the legacy entry so it can't linger as a ghost.
    private func migrateLegacyUnscopedItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(Self.accountPrefix),
                  item[kSecAttrService as String] as? String == nil,
                  let legacyData = item[kSecValueData as String] as? Data else { continue }
            let teamName = String(account.dropFirst(Self.accountPrefix.count))
            // Prefer the scoped entry when the team was re-added after
            // the upgrade — the user deliberately re-entered it.
            let winner = scopedItemData(forKey: teamName) ?? legacyData
            // Deletes by account alone, matching both the legacy entry
            // and any scoped duplicate; the winner is re-added below.
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account
            ] as CFDictionary)
            var add = Self.baseQuery(forKey: teamName)
            add[kSecValueData as String] = winner
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Raw data of the service-scoped item, if one exists.
    private func scopedItemData(forKey key: String) -> Data? {
        var query = Self.baseQuery(forKey: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    var getTeams: [String] {
        return getAllKeysFromKeychain()
            .map { $0.replacingOccurrences(of: Self.accountPrefix, with: "") }
    }

    var selectedTeam: Credential?

    var changeTeam: String? {
        get {
            if let selectedTeam = selectedTeam {
                return selectedTeam.key
            }
            return getTeams.first ?? nil
        }
        set {
            selectedTeam = newValue == nil ? nil : getCredential(key: newValue!)
        }
    }

    var getCredential: ((String) -> Credential?) {
        return { key in
            return CredentialStorage.shared.getCredential(key: key)
        }
    }

    func saveData(credential: Credential, teamName: String) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(credential)
            let query = Self.baseQuery(forKey: teamName)
            // Update in place when the item already exists; add otherwise.
            var existsCheck = query
            existsCheck[kSecMatchLimit as String] = kSecMatchLimitOne
            existsCheck[kSecReturnData as String] = false
            var ignored: AnyObject?
            let exists = SecItemCopyMatching(existsCheck as CFDictionary, &ignored) == errSecSuccess
            if exists {
                SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            } else {
                var addQuery = query
                addQuery[kSecValueData as String] = data
                addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
                SecItemAdd(addQuery as CFDictionary, nil)
            }
        } catch {}
    }

    func getCredential(key: String) -> Credential? {
        do {
            var query = Self.baseQuery(forKey: key)
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecReturnData as String] = true
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data else { return nil }
            let decoder = JSONDecoder()
            return try decoder.decode(Credential.self, from: data)
        } catch {}

        return nil
    }

    @discardableResult
    func deleteCredential(for key: String) -> Bool {
        // errSecItemNotFound → false preserves the old "already gone" contract.
        let deleted = SecItemDelete(Self.baseQuery(forKey: key) as CFDictionary) == errSecSuccess
        // Drop the in-memory credential too: otherwise a stale selectedTeam
        // keeps signing API requests after its keychain entry is gone.
        if deleted, selectedTeam?.key == key {
            selectedTeam = nil
        }
        return deleted
    }

    @discardableResult
    func restoreDefaultTeam() -> Bool {
        let teams = getTeams
        guard !teams.isEmpty else { return false }
        changeTeam = teams.first
        return true
    }
}

extension CredentialStorage {
    /// Every query is scoped by kSecAttrService + kSecAttrAccount —
    /// no global dump, only this service's items are ever touched.
    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountPrefix + key
        ]
    }

    private func getAllKeysFromKeychain() -> [String] {
        // Scoped by kSecAttrService — only items belonging to this
        // service are returned, never a global keychain dump.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }

        return items.compactMap { item -> String? in
            if let account = item[kSecAttrAccount as String] as? String {
                return account
            }
            return nil
        }
        .filter { $0.hasPrefix(Self.accountPrefix) }
    }
}
