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
    
    private init() { }
    
    var getTeams: [String] {
        return KeychainHelper.getAllKeysFromKeychain().filter({ $0.contains("App_Store_Connect_API_")})
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
            print("Encoded Data: \(data)")
        } catch {
            print("Error encoding credential: \(error)")
        }
    }
    
    func getCredential(key: String) -> Credential? {
        do {
            if let data = CredentialStorage.keychain.getData(key) {
                let decoder = JSONDecoder()
                return try decoder.decode(Credential.self, from: data)
            }
        } catch {
            print("Error encoding credential: \(error)")
        }
        
        return nil
    }
}
