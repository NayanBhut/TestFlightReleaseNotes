//
//  ContentViewSpine.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

struct ContentViewSpine: View {
    @StateObject var viewModelSpine : SideBarViewSpineModel
    
    var body: some View {
        let _ = Self._printChanges()
        NavigationSplitView {
            SideBarViewSpine(viewModel: SideBarViewSpineModel(getVersion: { (selectedApp, arrVersions, currentTeam, currentAppState) in
                self.viewModelSpine.selectedApp = selectedApp
                self.viewModelSpine.arrVersion = arrVersions
                self.viewModelSpine.currentTeam = currentTeam
                self.viewModelSpine.currentAppState = currentAppState
            }))
        } detail: {
            VStack(alignment: .center){
                DetailViewSpine(viewModel: DetailViewSpineModel(selectedApp: viewModelSpine.selectedApp, arrVersions: viewModelSpine.arrVersion, currentTeam: viewModelSpine.currentTeam, currentAppState: viewModelSpine.currentAppState))
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
}

#Preview {
    ContentViewSpine(viewModelSpine: SideBarViewSpineModel(getVersion: {_,_,_,_ in}))
}
