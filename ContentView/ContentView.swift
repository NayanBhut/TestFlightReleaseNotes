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

    init(viewModel: SideBarViewModel) {
        self.viewModel = viewModel
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(sidebarViewModel: viewModel))
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                SideBarView(viewModel: viewModel, isAddNewTeam: $showAlertView, isNewAccountAdded: $isNewAccountAdded)
                    .environmentObject(navigationManager)
            } detail: {
                VStack(alignment: .center){
                    DetailView(viewModel: detailViewModel)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showAlertView {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        showAlertView = false
                    }

                OnBoardingView(isLoggedIn: $isNewAccountAdded, isShowing: $showAlertView)
                    .frame(width: 500)
                    .background(Color.clear)
                    .cornerRadius(10)
                    .shadow(radius: 10)
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
            .environmentObject(ExportManager())
    }
}
