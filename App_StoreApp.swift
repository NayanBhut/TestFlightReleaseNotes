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
    @State private var showOnboarding = true

    var body: some View {
        ContentView()
            .environmentObject(navigationManager)
            .sheet(isPresented: $showOnboarding) {
                OnBoardingView(isLoggedIn: $navigationManager.isLoggedIn)
                    .environmentObject(navigationManager)
                    .presentationCornerRadius(20)
                    .presentationBackground(.thinMaterial)
            }
            .onAppear {
                navigationManager.checkLoginState()
                // Show onboarding sheet if not logged in
                showOnboarding = !navigationManager.isLoggedIn
            }
            .onChange(of: navigationManager.isLoggedIn) { newValue in
                showOnboarding = !newValue
            }
    }
}
