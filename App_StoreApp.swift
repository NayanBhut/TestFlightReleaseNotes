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
            RootView(viewModel: viewModel)
                .environmentObject(navigationManager)
                .environmentObject(exportManager)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var navigationManager: NavigationManager
    // Passed in directly — the sidebar view model flows through init params
    // only; the environment carries objects shared by unrelated views.
    private let viewModel: SideBarViewModel
    @State private var showOnboarding = true

    init(viewModel: SideBarViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ContentView(viewModel: viewModel)
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
