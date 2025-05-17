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
        isLoggedIn = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isLoggedIn)
    }
}

struct UserDefaultsKeys {
    static let isLoggedIn = "isLoggedIn"
}
