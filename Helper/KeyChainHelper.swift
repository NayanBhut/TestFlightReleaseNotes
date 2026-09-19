//
//  CredentialStorage.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import Foundation
import KeychainSwift
import Security

struct Credential: Codable {
    let key: String
    let issuerID: String
    let privateKey: String
    let keyID: String
}

final class CredentialStorage {
    static var shared: CredentialStorage = .init()
    static let keychain = KeychainSwift(keyPrefix: "App_Store_Connect_API_")
    
    private init() {
        if selectedTeam == nil {
            restoreDefaultTeam()
        }
    }
    
    var getTeams: [String] {
        return getAllKeysFromKeychain()
            .map { $0.replacingOccurrences(of: "App_Store_Connect_API_", with: "") }
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
            CredentialStorage.keychain.set(data, forKey: teamName, withAccess: .accessibleWhenUnlocked)
        } catch {}
    }
    
    func getCredential(key: String) -> Credential? {
        do {
            if let data = CredentialStorage.keychain.getData(key) {
                let decoder = JSONDecoder()
                return try decoder.decode(Credential.self, from: data)
            }
        } catch {}
        
        return nil
    }
    
    @discardableResult
    func deleteCredential(for key: String) -> Bool {
        guard getCredential(key: key) != nil else { return false }
        return CredentialStorage.keychain.delete(key)
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
    private func getAllKeysFromKeychain() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
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
        .filter { $0.hasPrefix("App_Store_Connect_API_") }
    }
}
