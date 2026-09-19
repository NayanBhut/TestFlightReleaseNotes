//
//  OnBoardingViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI
import UniformTypeIdentifiers

class OnBoardingViewModel: ObservableObject {
    @Published var teamName: String = ""
    @Published var issuerID: String = ""
    @Published var keyId: String = ""
    @Published var privateKey: String = ""
    @Published var isShowSpinner = false
    @Published var errorMessage: String?
    
    var isFormValid: Bool {
        !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var isJWTValid: Bool {
        guard !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        do {
            _ = try JWT(keyIdentifier: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
                        issuerIdentifier: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
                        expireDuration: 60 * 20)
            return true
        } catch {
            return false
        }
    }
    
    var isContinueEnabled: Bool {
        isFormValid && isJWTValid
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
                                expireDuration: 60 * 20).signedToken(using: privateKey.trimmingCharacters(in: .whitespacesAndNewlines)) {
            requestHeader["Authorization"] = "Bearer " + token
        }
        return requestHeader
    }
    
    func saveLoginState(isLoggedIn: Bool) {
        UserDefaults.standard.set(isLoggedIn, forKey: UserDefaultsKeys.isLoggedIn)
        let cleanTeamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        CredentialStorage.shared.saveData(credential: Credential(key: cleanTeamName, issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines), privateKey: privateKey.trimmingCharacters(in: .whitespacesAndNewlines), keyID: keyId.trimmingCharacters(in: .whitespacesAndNewlines)), teamName: cleanTeamName)
    }
    
    func getPrivateKey(filePath: URL?) {
        if let filePath = filePath, let data = try? Data(contentsOf: filePath) {
            let strData = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            privateKey = strData
        }
    }
    
    func showOpenPanel() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Open"
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.title = "Open Folder"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "p8")!]
        let response = openPanel.runModal()
        return response == .OK ? openPanel.url : nil
    }
    
    var isDuplicateTeam: Bool {
        let cleanTeamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CredentialStorage.shared.getTeams.contains(cleanTeamName)
    }
}