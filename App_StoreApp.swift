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
    private let viewModel: SideBarViewModel

    init(viewModel: SideBarViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ContentView(viewModel: viewModel)
            .environmentObject(navigationManager)
    }
}
