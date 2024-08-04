//
//  ContentView.swift
//  App Store
//
//  Created by Nayan Bhut on 18/08/23.
//

import SwiftUI
import AppStoreConnect_Swift_SDK

struct ContentView: View {
    @StateObject var viewModel : ContentViewModel

    var body: some View {
        let _ = Self._printChanges()
        NavigationSplitView {
            SideBarView()
        } detail: {
            VStack(alignment: .center){
                DetailView()
                if viewModel.isAppVersionsLoaded {
                    VersionAndBuildsView()
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.environmentObject(viewModel)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: ContentViewModel())
    }
}
