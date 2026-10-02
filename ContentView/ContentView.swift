//
//  ContentView.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SideBarViewModel
    @ObservedObject var monitor: BuildProcessingMonitor
    @StateObject var detailViewModel: DetailViewModel
    @EnvironmentObject var navigationManager: NavigationManager
    @State var showAlertView: Bool = false
    @State var isNewAccountAdded: Bool = false
    /// Observed so the layout flips between the full-window starting page
    /// and the split view the moment the first/last team is added/removed.
    @ObservedObject private var credentialStorage = CredentialStorage.shared

    init(viewModel: SideBarViewModel, monitor: BuildProcessingMonitor) {
        self.viewModel = viewModel
        self.monitor = monitor
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(sidebarViewModel: viewModel))
    }

    var body: some View {
        ZStack {
            if credentialStorage.teams.isEmpty {
                // No team yet: full-window starting page, no sidebar —
                // matches the Figma first-launch frames.
                FirstLaunchView(onAddKey: { showAlertView = true })
            } else {
                ShipyardShell(
                    sidebarVM: viewModel,
                    detailVM: detailViewModel,
                    monitor: monitor,
                    onAddTeam: { showAlertView = true }
                )
            }

            if showAlertView {
                AppTheme.overlay
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        showAlertView = false
                    }

                LaunchAssistantSheet(isShowing: $showAlertView, isLoggedIn: $isNewAccountAdded)
                    .onChange(of: isNewAccountAdded) { oldValue, newValue in
                        if newValue {
                            showAlertView = false
                        }
                    }
            }
        }
    }
}

#Preview {
    // A @StateObject holder mirrors production ownership so the preview
    // object survives re-renders instead of resetting while iterating.
    ContentViewPreview()
}

private struct ContentViewPreview: View {
    @StateObject private var viewModel = SideBarViewModel()
    @StateObject private var monitor = BuildProcessingMonitor()

    var body: some View {
        ContentView(viewModel: viewModel, monitor: monitor)
            .environmentObject(NavigationManager())
    }
}
