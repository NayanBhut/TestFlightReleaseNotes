//
//  OnBoardingViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI
import UniformTypeIdentifiers

@MainActor
class OnBoardingViewModel: ObservableObject {
    @Published var teamName: String = ""
    @Published var issuerID: String = ""
    @Published var keyId: String = ""
    @Published var privateKey: String = ""
    @Published var isShowSpinner = false
    @Published var errorMessage: String?

    private static let maxPrivateKeyFileBytes = 64 * 1024
    
    var isFormValid: Bool {
        !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Cached so repeated SwiftUI body evaluations don't re-sign the EC
    /// key on every keystroke — only when an input actually changes.
    private var jwtValidationCache: (inputs: String, isValid: Bool)?
    
    var isJWTValid: Bool {
        guard !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        let inputs = "\(keyId)|\(issuerID)|\(privateKey)"
        if let cache = jwtValidationCache, cache.inputs == inputs {
            return cache.isValid
        }
        // Actually sign: the JWT initializer is non-throwing, so only a
        // successful signedToken() proves the credentials work.
        let isValid = (try? JWT(
            keyIdentifier: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerIdentifier: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            expireDuration: JWTLimits.expiryInterval
        ).signedToken(using: privateKey.trimmingCharacters(in: .whitespacesAndNewlines))) != nil
        jwtValidationCache = (inputs, isValid)
        return isValid
    }
    
    var isContinueEnabled: Bool {
        isFormValid && isJWTValid && !isDuplicateTeam
    }
    
    func getAllApps(completion: @escaping ((Bool) -> Void)) {
        guard isFormValid else {
            errorMessage = "Please fill in all required fields"
            return
        }
        
        guard isJWTValid else {
            errorMessage = "Invalid JWT credentials"
            completion(false)
            return
        }
        
        let queryParams = [
            "include": "appStoreVersions",
            "filter[appStoreVersions.platform]": "IOS",
            "sort": "-name"
        ]
        
        guard let request = APIClient.shared.getRequest(header: getHeader(), api: .get(name: .getAllApps, queryParams: queryParams), apiVersion: .v1) else {
            errorMessage = "Failed to create request"
            return
        }
        
        isShowSpinner = true
        errorMessage = nil
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            self.isShowSpinner = false
            
            switch result {
            case .success(let successData):
                do {
                    let model = try getDecoder().decode([AppsData].self, from: successData)
                    
                    if model.isEmpty {
                        self.errorMessage = "No apps found for this team"
                        completion(false)
                    } else {
                        self.errorMessage = nil
                        completion(true)
                    }
                } catch {
                    self.errorMessage = "Invalid response from server"
                    completion(false)
                }
            case .failure(let failure):
                self.errorMessage = "Authentication failed. Please check your credentials."
                completion(false)
            }
        }
    }
    
    private func getHeader() -> [String: String] {
        var requestHeader = ["Content-Type": "application/json"]
        if let token = try? JWT(keyIdentifier: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
                                issuerIdentifier: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
                                expireDuration: JWTLimits.expiryInterval).signedToken(using: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
            requestHeader["Authorization"] = "Bearer " + token
        }
        return requestHeader
    }
    
    /// Returns false when the keychain write fails — the caller must not
    /// treat the team as added without a stored, working credential. No
    /// persisted login flag is written: CredentialStorage's published
    /// teams list is the single source of truth for login state.
    @discardableResult
    func saveLoginState() -> Bool {
        let cleanTeamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CredentialStorage.shared.saveData(credential: Credential(key: cleanTeamName, issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines), privateKey: privateKey.trimmingCharacters(in: .whitespacesAndNewlines), keyID: keyId.trimmingCharacters(in: .whitespacesAndNewlines)), teamName: cleanTeamName) else {
            errorMessage = "Couldn't save the team to the Keychain. Please try again."
            return false
        }
        // Select immediately so API requests work, even when the sidebar's
        // onAppear (which restores the default team) already ran before login.
        CredentialStorage.shared.changeTeam = cleanTeamName
        return true
    }
    
    func getPrivateKey(filePath: URL?) {
        guard let filePath else { return }
        errorMessage = nil
        Task {
            do {
                let data = try await Self.loadPrivateKeyData(from: filePath)
                let strData = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    privateKey = strData
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn't read that .p8 file. Choose the API key file downloaded from App Store Connect."
                }
            }
        }
    }

    private static func loadPrivateKeyData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > maxPrivateKeyFileBytes {
                throw CocoaError(.fileReadTooLarge)
            }
            return try Data(contentsOf: url, options: [.mappedIfSafe])
        }.value
    }
    
    func showOpenPanel() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Choose"
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.title = "Select your App Store Connect API key"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "p8")!]
        let response = openPanel.runModal()
        return response == .OK ? openPanel.url : nil
    }
    
    var isDuplicateTeam: Bool {
        let cleanTeamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleanTeamName.isEmpty && CredentialStorage.shared.getTeams.contains(cleanTeamName)
    }
}
