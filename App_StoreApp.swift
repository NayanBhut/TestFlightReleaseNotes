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
    /// Batch H: build-processing poller backing the menu bar extra. Started
    /// idempotently from both scenes — whichever appears first wins.
    @StateObject private var buildMonitor = BuildProcessingMonitor()

    var body: some Scene {
        // id "main" is referenced by the menu bar extra's "Open App" item.
        WindowGroup(id: "main") {
            RootView(viewModel: viewModel)
                .environmentObject(navigationManager)
                .environmentObject(exportManager)
                .task {
                    buildMonitor.start()
                }
        }

        MenuBarExtra {
            MenuBarBuildsView(monitor: buildMonitor)
        } label: {
            // Icon-only while idle (menu bar space is precious); the count
            // appears only when there's something processing.
            if buildMonitor.processingCount > 0 {
                Label("\(buildMonitor.processingCount)", systemImage: "hourglass")
            } else {
                Image(systemName: "shippingbox")
            }
        }
        .menuBarExtraStyle(.menu)
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
