//
//  OnBoardingViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI
import UniformTypeIdentifiers

class OnBoardingViewModel: ObservableObject {
    @Published var teamName: String = "UA"
    @Published var issuerID: String = "e34e806a-b679-45ae-96c0-06baaed42c57"
    @Published var keyId: String = "QPC7C8YQAA"
    @Published var privateKey: String = ""
    @Published var isShowSpinner = false
    
    func getAllApps(completion: @escaping ((Bool) -> Void)) {
        let queryParams = ["include": "appStoreVersions",
                           "filter[appStoreVersions.platform]": "IOS",
                           "sort": "-name",
        ]
        
        guard let request = APIClient.shared.getRequest(header: getHeader(), api: .get(name: .getAllApps,queryParams: queryParams), apiVersion: .v1) else { return }
        
        isShowSpinner = true
        
        APIClient.shared.callAPI(with: request) {[weak self] result in
            self?.isShowSpinner = false
            switch result {
            case .success(let successData):
                print("API Model getAllApps Data is ", successData)
                
                do {
                    let model = try getDecoder().decode([AppsData].self, from: successData)
                    print("Model data is ", model)
                    completion(true)
                } catch {
                    print("API Error is ")
                    completion(false)
                }
            case .failure(let failure):
                print("API Error is ", failure)
                completion(false)
            }
        }
    }
    
    private func getHeader() -> [String: String] {
        var requestHeader = ["Content-Type": "application/json"]
        if let token = try? JWT(keyIdentifier: keyId, issuerIdentifier: issuerID, expireDuration: 60 * 20).signedToken(using: privateKey) {
            requestHeader["Authorization"] = "Bearer " + token
        }
        return requestHeader
    }
    
    func saveLoginState(isLoggedIn: Bool) {
        UserDefaults.standard.set(isLoggedIn, forKey: UserDefaultsKeys.isLoggedIn)
        CredentialStorage.shared.saveData(credential: Credential(key: teamName, issuerID: issuerID, privateKey: privateKey, keyID: keyId), teamName: teamName)
    }
    
    func getPrivateKey(filePath: URL?) {
        if let filePath = filePath, let data = try? Data(contentsOf: filePath) {
            let strData = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
                .replacingOccurrences(of: "\n", with: "")
            privateKey = strData
        }
    }
    
    func showOpenPanel() -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.prompt = "Open"
        openPanel.canChooseFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.title = "Open Folder"
        openPanel.allowedContentTypes = [UTType(filenameExtension: "p8")!]
        let response = openPanel.runModal()
        return response == .OK ? openPanel.url : nil
    }
}
