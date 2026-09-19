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
    @StateObject private var viewModel = SideBarViewModel()
    @StateObject private var exportManager = ExportManager()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(navigationManager)
                .environmentObject(viewModel)
                .environmentObject(exportManager)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    @EnvironmentObject var viewModel: SideBarViewModel
    @EnvironmentObject var exportManager: ExportManager
    @State private var showOnboarding = true

    var body: some View {
        ContentView(viewModel: viewModel, exportManager: exportManager)
            .environmentObject(navigationManager)
            .sheet(isPresented: $showOnboarding) {
                OnBoardingView(isLoggedIn: $navigationManager.isLoggedIn)
                    .environmentObject(navigationManager)
                    .presentationCornerRadius(20)
                    .presentationBackground(.thinMaterial)
            }
            .onAppear {
                navigationManager.checkLoginState()
                showOnboarding = !navigationManager.isLoggedIn
            }
            .onChange(of: navigationManager.isLoggedIn) { newValue in
                showOnboarding = !newValue
            }
    }
}
