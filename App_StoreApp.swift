//
//  App_StoreApp.swift
//  App Store
//
//  Created by Nayan Bhut on 18/08/23.
//

import SwiftUI
import AppKit

@main
struct App_StoreApp: App {
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var viewModel = SideBarViewModel()
    @StateObject private var buildMonitor = BuildProcessingMonitor()
    @StateObject private var appCommands = AppCommandStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(viewModel: viewModel, monitor: buildMonitor)
                .environmentObject(navigationManager)
                .environmentObject(appCommands)
                .sheet(isPresented: $appCommands.showPalette) {
                    CommandPalette(commands: appCommands)
                }
                .task {
                    buildMonitor.start()
                    AppAppearance.applyStored()
                    clampMainWindowToVisibleScreen()
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
        .defaultSize(width: 1280, height: 800)
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

/// One-time safety: a window frame restored from a larger display can end
/// up wider than the current screen, pushing centered content off-screen
/// with no visible edge to grab. Shrink only the width overflow on the
/// window's own screen — never grow, move, or touch height — so
/// multi-display setups are unaffected.
private func clampMainWindowToVisibleScreen() {
    guard let window = NSApp.keyWindow
        ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
        let screen = window.screen else { return }
    let visible = screen.visibleFrame
    var frame = window.frame
    guard frame.width > visible.width else { return }
    frame.size.width = visible.width
    if frame.minX < visible.minX {
        frame.origin.x = visible.minX
    }
    window.setFrame(frame, display: true)
}