//
//  ContentView.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SideBarViewModel
    @StateObject var detailViewModel: DetailViewModel
    @EnvironmentObject var navigationManager: NavigationManager
    @State var showAlertView: Bool = false
    @State var isNewAccountAdded: Bool = false
    /// Observed so the layout flips between the full-window starting page
    /// and the split view the moment the first/last team is added/removed.
    @ObservedObject private var credentialStorage = CredentialStorage.shared

    init(viewModel: SideBarViewModel) {
        self.viewModel = viewModel
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(sidebarViewModel: viewModel))
    }

    var body: some View {
        ZStack {
            if credentialStorage.teams.isEmpty {
                // No team yet: full-window starting page, no sidebar —
                // matches the Figma first-launch frames.
                FirstLaunchView(onAddKey: { showAlertView = true })
            } else {
                NavigationSplitView {
                    SideBarView(viewModel: viewModel, isAddNewTeam: $showAlertView, isNewAccountAdded: $isNewAccountAdded)
                        .environmentObject(navigationManager)
                } detail: {
                    VStack(alignment: .center){
                        DetailView(viewModel: detailViewModel, onAddTeam: { showAlertView = true })
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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

    var body: some View {
        ContentView(viewModel: viewModel)
            .environmentObject(NavigationManager())
    }
}
