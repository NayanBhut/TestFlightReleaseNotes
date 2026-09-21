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
        WindowGroup {
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
            // Count in the label so an uploaded build is visible at a glance.
            Label(
                buildMonitor.processingCount > 0
                    ? "\(buildMonitor.processingCount) processing"
                    : "Builds",
                systemImage: buildMonitor.processingCount > 0 ? "hourglass" : "checkmark.circle"
            )
            .task {
                buildMonitor.start()
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
