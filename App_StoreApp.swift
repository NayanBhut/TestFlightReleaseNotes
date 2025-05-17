//
//  App_StoreApp.swift
//  App Store
//
//  Created by Nayan Bhut on 18/08/23.
//

import SwiftUI

@main
struct App_StoreApp: App {
    @StateObject private var navigationManager = NavigationManager()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(navigationManager)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var navigationManager: NavigationManager

    var body: some View {
        Group {
            if navigationManager.isLoggedIn {
                ContentView()
                    .environmentObject(navigationManager)
            } else {
                OnBoardingView(isLoggedIn: $navigationManager.isLoggedIn)
            }
        }
        .onAppear {
            navigationManager.checkLoginState()
        }
    }
}
