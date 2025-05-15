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
    
    init() {
        let sidebarVM = SideBarViewModel()
        _viewModel = StateObject(wrappedValue: sidebarVM)
        _detailViewModel = StateObject(wrappedValue: DetailViewModel(sidebarViewModel: sidebarVM))
    }
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationSplitView {
            SideBarView(viewModel: viewModel)
        } detail: {
            VStack(alignment: .center){
                DetailView(viewModel: detailViewModel)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
}

#Preview {
    ContentView()
}
