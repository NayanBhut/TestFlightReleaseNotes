//
//  AESHelper.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import Foundation
import CommonCrypto

struct AESHelper {

    private static let key = "your-secret-key" // Use a secure key in production
    private static let iv = "your-iv-vector"   // Use a secure IV in production

    static func encrypt(data: Data) -> Data? {
        guard key.count == kCCKeySizeAES256 || key.count == kCCKeySizeAES128,
              iv.count == kCCBlockSizeAES128 else {
            return nil
        }

        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)

        var numBytesEncrypted: size_t = 0

        let cryptStatus = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                CCCrypt(
                    CCOperation(kCCEncrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    key,
                    key.count,
                    iv,
                    dataBytes.baseAddress,
                    data.count,
                    cryptBytes.baseAddress,
                    cryptLength,
                    &numBytesEncrypted
                )
            }
        }

        if cryptStatus == kCCSuccess {
            cryptData.count = numBytesEncrypted
            return cryptData
        }

        return nil
    }

    static func decrypt(data: Data) -> Data? {
        guard key.count == kCCKeySizeAES256 || key.count == kCCKeySizeAES128,
              iv.count == kCCBlockSizeAES128 else {
            return nil
        }

        let cryptLength = data.count + kCCBlockSizeAES128
        var cryptData = Data(count: cryptLength)

        var numBytesDecrypted: size_t = 0

        let cryptStatus = cryptData.withUnsafeMutableBytes { cryptBytes in
            data.withUnsafeBytes { dataBytes in
                CCCrypt(
                    CCOperation(kCCDecrypt),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCOptions(kCCOptionPKCS7Padding),
                    key,
                    key.count,
                    iv,
                    dataBytes.baseAddress,
                    data.count,
                    cryptBytes.baseAddress,
                    cryptLength,
                    &numBytesDecrypted
                )
            }
        }

        if cryptStatus == kCCSuccess {
            cryptData.count = numBytesDecrypted
            return cryptData
        }

        return nil
    }
}

enum KeychainHelper {
    static func save(key: String, data: Data) -> Bool {
        if let encryptedData = AESHelper.encrypt(data: data) {
            let query = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: encryptedData
            ] as [String: Any]

            SecItemDelete(query as CFDictionary)
            let status = SecItemAdd(query as CFDictionary, nil)
            return status == errSecSuccess
        }
        return false
    }

    static func load(key: String) -> Data? {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ] as [String: Any]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let encryptedData = dataTypeRef as? Data {
            return AESHelper.decrypt(data: encryptedData)
        } else {
            return nil
        }
    }

    static func delete(key: String) -> Bool {
        let query = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ] as [String: Any]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess
    }
    
    static func getAllKeysFromKeychain() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        var keys: [String] = []

        if status == errSecSuccess, let items = result as? [[String: Any]] {
            for item in items {
                if let key = item[kSecAttrAccount as String] as? String {
                    keys.append(key)
                }
            }
        }

        return keys
    }
}
