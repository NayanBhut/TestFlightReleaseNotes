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
    @StateObject private var buildMonitor = BuildProcessingMonitor()
    @StateObject private var appCommands = AppCommandStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel)
                .environmentObject(navigationManager)
                .environmentObject(appCommands)
                .sheet(isPresented: $appCommands.showPalette) {
                    CommandPalette(commands: appCommands)
                }
                .task {
                    buildMonitor.start()
                    AppAppearance.applyStored()
                }
                .onReceive(appCommands.refreshRequested) { _ in
                    viewModel.retryApps()
                }
                .onReceive(appCommands.clearSearchRequested) { _ in
                    viewModel.clearSearch()
                }
                .onReceive(appCommands.toggleDarkModeRequested) { _ in
                    AppAppearance.toggle()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Command Palette") {
                    appCommands.showPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
                Button("Toggle Dark Mode") {
                    appCommands.requestToggleDarkMode()
                }
                .keyboardShortcut("d", modifiers: .command)
                Button("Refresh") {
                    appCommands.requestRefresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarBuildsView(monitor: buildMonitor)
        } label: {
            if buildMonitor.processingCount > 0 {
                Label("\(buildMonitor.processingCount)", systemImage: "hourglass")
            } else {
                Image(systemName: "shippingbox")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}