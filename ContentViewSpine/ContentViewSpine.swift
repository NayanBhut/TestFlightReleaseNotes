//
//  ContentViewSpine.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct ContentViewSpine: View {
    @StateObject private var viewModelSpine = SideBarViewSpineModel()
    @StateObject private var detailViewModel: DetailViewSpineModel
    
    init() {
        let sidebarVM = SideBarViewSpineModel()
        _viewModelSpine = StateObject(wrappedValue: sidebarVM)
        _detailViewModel = StateObject(wrappedValue: DetailViewSpineModel(sidebarViewModel: sidebarVM))
    }
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationSplitView {
            SideBarViewSpine(viewModel: viewModelSpine)
        } detail: {
            VStack(alignment: .center){
                DetailViewSpine(viewModel: detailViewModel)
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
}

#Preview {
    ContentViewSpine()
}
