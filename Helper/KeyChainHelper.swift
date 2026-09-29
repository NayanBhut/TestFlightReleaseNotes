//
//  CredentialStorage.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import Combine
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

@MainActor
final class CredentialStorage: ObservableObject {
    static let shared: CredentialStorage = .init()

    /// Scopes every keychain item to this service so credentials from
    /// other services are never read, written, or listed.
    private static let service = "com.appstore.release-notes"
    private static let accountPrefix = "App_Store_Connect_API_"

    /// UserDefaults key remembering the last-selected team so a relaunch
    /// restores the active account instead of falling back to an arbitrary
    /// (keychain-order) first team. The secret itself stays in the keychain —
    /// only the team *name* is persisted here.
    private static let selectedTeamNameKey = "selectedTeamName"
    /// One-time migration flag. Set only after a *successful* scan/migration
    /// so a transient keychain error retries on next launch instead of being
    /// skipped forever — but a completed migration never re-scans.
    private static let legacyMigrationDoneKey = "legacyKeychainMigrationDone"

    /// In-memory mirror of the keychain's team names. Published so SwiftUI
    /// views re-render when teams are added/removed (a bare
    /// `CredentialStorage.shared.getTeams` read inside body is an
    /// untracked dependency), and cached so body evaluations never hit
    /// the keychain. Refreshed by the membership-changing mutations below.
    @Published private(set) var teams: [String] = []

    /// The active credential. Published (not a bare var) so views observing
    /// CredentialStorage re-render on account switch even when the team list
    /// itself is unchanged. Backed by the keychain; mirrored here plus a
    /// per-team cache so switching accounts doesn't hit the keychain (and
    /// its potential auth prompt) on every switch.
    @Published private(set) var selectedTeam: Credential?

    /// Decoded-credential cache. Warmed lazily on selection — never bulk-read
    /// at launch, so the app prompts at most once per team actually used.
    private var credentialCache: [String: Credential] = [:]

    /// Teams whose keychain read failed this session (denied prompt, locked
    /// keychain, orphaned pre-sandbox item…). Remembered so every view
    /// re-render / team restore doesn't re-trigger the system prompt for the
    /// same unreadable team. Evicted on save/delete and pruned whenever the
    /// team list refreshes.
    private var unreadableTeams: Set<String> = []

    private init() {
        migrateLegacyUnscopedItemsIfNeeded()
        refreshTeams()
        if selectedTeam == nil {
            restoreDefaultTeam()
        }
    }

    /// One-time upgrade path: KeychainSwift stored items with no
    /// kSecAttrService, so pre-scoping teams are invisible to the
    /// service-scoped queries.
    ///
    /// The global (unscoped) attributes scan runs at most once: a
    /// UserDefaults flag is set only after a *successful* pass, so a
    /// transient keychain error still retries on next launch, while a
    /// completed migration never re-scans the whole login keychain (that
    /// repeat scan was prompting for keychain access on every launch).
    private func migrateLegacyUnscopedItemsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.legacyMigrationDoneKey) else { return }
        // Phase 1: ATTRIBUTES ONLY — data of other services' passwords
        // never leaves the keychain; nothing unrelated is read or prompted.
        let scan: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false
        ]
        var scanResult: AnyObject?
        let scanStatus = SecItemCopyMatching(scan as CFDictionary, &scanResult)
        guard scanStatus == errSecSuccess,
              let items = scanResult as? [[String: Any]] else {
            // errSecItemNotFound just means an empty keychain — migration is
            // trivially done.
            if scanStatus == errSecItemNotFound {
                UserDefaults.standard.set(true, forKey: Self.legacyMigrationDoneKey)
                return
            }
            // The user denied the prompt: mark done and stop pestering.
            // Re-scanning every launch would re-prompt every launch. Legacy
            // items stay put — the user can re-add the team, which writes a
            // proper scoped item.
            // errSecUserCanceled is the canonical macOS "Deny" result;
            // errSecAuthFailed covers a locked keychain / refused access.
            // errSecInteractionNotAllowed is deliberately NOT here: it's
            // transient (early boot / no UI yet) and retrying is safe (no
            // prompt can appear when interaction isn't allowed).
            if scanStatus == errSecAuthFailed || scanStatus == errSecUserCanceled {
                keychainLogger.error("Migration scan denied (OSStatus \(scanStatus)); skipping future scans")
                UserDefaults.standard.set(true, forKey: Self.legacyMigrationDoneKey)
                return
            }
            // Any other status (incl. errSecInteractionNotAllowed) is
            // transient: don't set the flag so the next launch retries.
            return
        }
        let legacyAccounts = items.compactMap { item -> String? in
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(Self.accountPrefix),
                  item[kSecAttrService as String] as? String == nil else { return nil }
            return account
        }
        guard !legacyAccounts.isEmpty else {
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationDoneKey)
            return
        }

        var hadFailure = false
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
                hadFailure = true
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

            var add = Self.addAttributes(forKey: teamName)
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
                hadFailure = true
            }
        }
        // Only a fully successful pass marks migration done — a partial
        // failure retries next launch instead of stranding a legacy item.
        if !hadFailure {
            UserDefaults.standard.set(true, forKey: Self.legacyMigrationDoneKey)
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

    /// Cached team names (kept for existing call sites). No keychain I/O.
    var getTeams: [String] {
        teams
    }

    /// Re-reads the keychain's team list into the published cache. Called
    /// only on membership-changing mutations (init/migration/save/delete).
    /// Sorted so the default-team fallback is stable across launches
    /// (keychain return order is undefined). Deduped: a re-added team can
    /// briefly twin its orphaned pre-sandbox item under the same name, and
    /// duplicate names would break ForEach(id: \.self) in the team picker.
    private func refreshTeams() {
        let names = getAllKeysFromKeychain()
            .map { $0.replacingOccurrences(of: Self.accountPrefix, with: "") }
        teams = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        unreadableTeams.formIntersection(teams)
    }

    var changeTeam: String? {
        get {
            if let selectedTeam = selectedTeam {
                return selectedTeam.key
            }
            return getTeams.first ?? nil
        }
        set {
            guard let name = newValue else {
                selectedTeam = nil
                UserDefaults.standard.removeObject(forKey: Self.selectedTeamNameKey)
                return
            }
            selectedTeam = getCredential(key: name)
            if selectedTeam != nil {
                UserDefaults.standard.set(name, forKey: Self.selectedTeamNameKey)
            }
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
            refreshTeams()
            credentialCache[teamName] = credential
            unreadableTeams.remove(teamName)
            return true
        } catch {
            keychainLogger.error("Credential encoding failed for '\(teamName, privacy: .public)'")
            return false
        }
    }

    /// Add, or update in place when the scoped item already exists.
    private func upsert(key: String, data: Data) -> OSStatus {
        var addQuery = Self.addAttributes(forKey: key)
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
        if let cached = credentialCache[key] {
            return cached
        }
        // Failed earlier this session (denied prompt etc.) — don't ask the
        // keychain (and the user) again for the same team.
        if unreadableTeams.contains(key) {
            return nil
        }
        var query = Self.baseQuery(forKey: key)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecAuthFailed || status == errSecUserCanceled {
                keychainLogger.error("Keychain read denied for '\(key, privacy: .public)' (OSStatus \(status)); won't retry this session")
            }
            unreadableTeams.insert(key)
            return nil
        }
        do {
            let credential = try JSONDecoder().decode(Credential.self, from: data)
            credentialCache[key] = credential
            return credential
        } catch {
            keychainLogger.error("Credential decoding failed for '\(key, privacy: .public)'")
            unreadableTeams.insert(key)
            return nil
        }
    }

    @discardableResult
    func deleteCredential(for key: String) -> Bool {
        // errSecItemNotFound → false preserves the old "already gone" contract.
        let deleted = SecItemDelete(Self.baseQuery(forKey: key) as CFDictionary) == errSecSuccess
        if deleted {
            credentialCache.removeValue(forKey: key)
            unreadableTeams.remove(key)
            // Drop the in-memory credential too: otherwise a stale selectedTeam
            // keeps signing API requests after its keychain entry is gone.
            if selectedTeam?.key == key {
                selectedTeam = nil
            }
            if UserDefaults.standard.string(forKey: Self.selectedTeamNameKey) == key {
                UserDefaults.standard.removeObject(forKey: Self.selectedTeamNameKey)
            }
            refreshTeams()
        }
        return deleted
    }

    /// Restores the last-used team when it still exists and is readable,
    /// otherwise falls back to the first (sorted) team. Persists the
    /// outcome so the next launch agrees. Falls back at most once so a
    /// denied/locked saved team doesn't leave the app with no active
    /// credential, while avoiding prompting for every team at launch.
    @discardableResult
    func restoreDefaultTeam() -> Bool {
        guard !teams.isEmpty else { return false }
        let saved = UserDefaults.standard.string(forKey: Self.selectedTeamNameKey)
        if let saved, teams.contains(saved) {
            changeTeam = saved
            if selectedTeam != nil { return true }
        }
        // Saved team missing or unreadable — fall back to the first *other*
        // team (avoids re-prompting for the same unreadable saved team).
        if let fallback = teams.first(where: { $0 != saved }) {
            changeTeam = fallback
        }
        return selectedTeam != nil
    }
}

extension CredentialStorage {
    /// Every query is scoped by kSecAttrService + kSecAttrAccount —
    /// no global dump, only this service's items are ever touched.
    /// Reads/deletes/listing use kSecAttrSynchronizableAny so items
    /// written by older app versions (without an explicit synchronizable
    /// attribute) still match; only SecItemAdd pins synchronizable=false
    /// to keep API secrets off iCloud Keychain.
    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountPrefix + key,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }

    /// Attributes for SecItemAdd. Same scope as baseQuery but pins
    /// synchronizable=false so the new item is local-only (never synced
    /// to iCloud Keychain).
    private static func addAttributes(forKey key: String) -> [String: Any] {
        var q = baseQuery(forKey: key)
        q[kSecAttrSynchronizable as String] = false
        return q
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
