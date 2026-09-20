//
//  CredentialStorage.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import Foundation
import Security
import OSLog

private let keychainLogger = Logger(subsystem: "com.appstore.release-notes", category: "Keychain")

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
    /// service-scoped queries. Idempotent by construction: once nothing
    /// unscoped matches, the attributes-only scan is a cheap no-op (a
    /// UserDefaults "done" flag is deliberately NOT used — it would
    /// permanently skip migration if the first launch hit a transient
    /// keychain error).
    private func migrateLegacyUnscopedItems() {
        // Phase 1: ATTRIBUTES ONLY — data of other services' passwords
        // never leaves the keychain; nothing unrelated is read or prompted.
        let scan: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false
        ]
        var scanResult: AnyObject?
        guard SecItemCopyMatching(scan as CFDictionary, &scanResult) == errSecSuccess,
              let items = scanResult as? [[String: Any]] else { return }
        let legacyAccounts = items.compactMap { item -> String? in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(Self.accountPrefix),
                  item[kSecAttrService as String] as? String == nil else { return nil }
            return account
        }
        guard !legacyAccounts.isEmpty else { return }

        for account in legacyAccounts {
            let teamName = String(account.dropFirst(Self.accountPrefix.count))
            // Phase 2a: fetch data only for OUR legacy item (exact account).
            let fetchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            var fetched: AnyObject?
            guard SecItemCopyMatching(fetchQuery as CFDictionary, &fetched) == errSecSuccess,
                  let legacyData = fetched as? Data else {
                keychainLogger.error("Migration: couldn't read legacy item '\(teamName, privacy: .public)'")
                continue
            }
            // Prefer the scoped entry when the team was re-added after the
            // upgrade — the user deliberately re-entered it.
            let winner = scopedItemData(forKey: teamName) ?? legacyData

            // Phase 2b: delete by account (the legacy item AND any scoped
            // twin — the upsert below replaces the twin's data), then write
            // the scoped item. On write failure, roll the legacy entry back
            // so migration can never destroy a credential.
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: account
            ] as CFDictionary)

            var add = Self.baseQuery(forKey: teamName)
            add[kSecValueData as String] = winner
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
                let rollback: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: account,
                    kSecValueData as String: legacyData,
                    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
                ]
                SecItemAdd(rollback as CFDictionary, nil)
                keychainLogger.error("Migration: scoped write failed for '\(teamName, privacy: .public)', legacy item restored")
            }
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

    /// Returns false when the keychain write fails so callers can refuse
    /// to proceed (onboarding must not log in with an unstored credential).
    @discardableResult
    func saveData(credential: Credential, teamName: String) -> Bool {
        do {
            let data = try JSONEncoder().encode(credential)
            let status = upsert(key: teamName, data: data)
            if status != errSecSuccess {
                keychainLogger.error("Keychain write failed for '\(teamName, privacy: .public)' (OSStatus \(status))")
                return false
            }
            return true
        } catch {
            keychainLogger.error("Credential encoding failed for '\(teamName, privacy: .public)'")
            return false
        }
    }

    /// Add, or update in place when the scoped item already exists.
    private func upsert(key: String, data: Data) -> OSStatus {
        var addQuery = Self.baseQuery(forKey: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            return SecItemUpdate(
                Self.baseQuery(forKey: key) as CFDictionary,
                [kSecValueData as String: data] as CFDictionary)
        }
        return status
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
