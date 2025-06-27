//
//  ContentView.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = SideBarViewModel()
    @StateObject private var detailViewModel: DetailViewModel
    @EnvironmentObject var navigationManager: NavigationManager
    @State var showAlertView: Bool = false
    @State var isNewAccountAdded: Bool = false
    
    init() {
        let sidebarVM = SideBarViewModel()
        _viewModel = StateObject(wrappedValue: sidebarVM)
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(sidebarViewModel: sidebarVM))
    }
    
    var body: some View {
        let _ = Self._printChanges()
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
                
                OnBoardingView(isLoggedIn: $isNewAccountAdded)
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
    ContentView()
        .environmentObject(NavigationManager())
}
