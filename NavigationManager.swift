//
//  NavigationManager.swift
//  App Store
//
//  Created by Nayan Bhut on 16/05/25.
//

import SwiftUI

class NavigationManager: ObservableObject {
    @Published var isLoggedIn: Bool = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isLoggedIn)

    func checkLoginState() {
        let loginState = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isLoggedIn)
        let teams = CredentialStorage.shared.getTeams
        
        if loginState && !teams.isEmpty {
            isLoggedIn = true
        } else {
            isLoggedIn = false
            UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.isLoggedIn)
        }
    }
}

struct UserDefaultsKeys {
    static let isLoggedIn = "isLoggedIn"
}
