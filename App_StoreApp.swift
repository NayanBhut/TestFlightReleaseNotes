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
    @StateObject private var buildMonitor = BuildProcessingMonitor()
    @StateObject private var appCommands = AppCommandStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            rootView
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

    @ViewBuilder
    private var rootView: some View {
#if DEBUG
        if let scenario = ReviewSubmissionUITestScenario.current {
            ReviewSubmissionUITestHost(scenario: scenario)
        } else {
            ProductionAppRoot(buildMonitor: buildMonitor, appCommands: appCommands)
        }
#else
        ProductionAppRoot(buildMonitor: buildMonitor, appCommands: appCommands)
#endif
    }
}

/// Keeps credential-backed production state out of the deterministic UI-test
/// launch path. Constructing this view is what opts into Keychain access.
private struct ProductionAppRoot: View {
    @ObservedObject var buildMonitor: BuildProcessingMonitor
    @ObservedObject var appCommands: AppCommandStore
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var viewModel = SideBarViewModel()

    var body: some View {
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
}

/// One-time safety: a window frame restored from a larger display can end
/// up wider than the current screen, pushing content off-screen with no
/// visible edge to grab. Shrinks width overflow and recentres when any
/// edge is offscreen. Only runs once on launch — never grows, changes
/// height, or fires on multi-display setups where the window fits.
private func clampMainWindowToVisibleScreen() {
    guard let window = NSApp.keyWindow
        ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) }),
        let screen = window.screen else { return }
    let visible = screen.visibleFrame
    var frame = window.frame
    var changed = false
    if frame.width > visible.width {
        frame.size.width = visible.width
        changed = true
    }
    if frame.minX < visible.minX {
        frame.origin.x = visible.minX
        changed = true
    } else if frame.maxX > visible.maxX {
        frame.origin.x = visible.maxX - frame.width
        if frame.minX < visible.minX {
            frame.origin.x = visible.minX
        }
        changed = true
    }
    guard changed else { return }
    window.setFrame(frame, display: true)
}
