//
//  VersionAndBuildView.swift
//  App Store
//
//  Created by Nayan Bhut on 19/04/24.
//

import SwiftUI

struct VersionAndBuildsView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    var body: some View {
        VStack {
            Text("Version and Build View")
            getBuildList()
        }.onAppear(){
            print("Total Versions are ",viewModel.getSelectedApp()?.arrVersions.count ?? "0")
        }
    }
    
    @ViewBuilder private func getBuildList() -> some View {
        if let selectedApp = viewModel.getSelectedApp(),
           let selectedVersion = viewModel.getSelectedVersion() {
            buildDetailView(selectedApp: selectedApp, selectedVersion: selectedVersion)
            HStack {
                Text("\(selectedApp.app.attributes?.name ?? "") => ")
                Text("\(selectedVersion.arrBuilds.count)")
            }
        } else {
            Text("Please select App Version")
        }
    }
    
    private func buildDetailView(selectedApp: AppDataModel, selectedVersion: VersionDataModel) -> some View {
        BuildDetailsView(getBuidsData: { buildID in
            viewModel.loadLocalizationfromAPI(appId: selectedApp.id, buildId: buildID)
        },setBuidsData: { buildId, localizationID, releaseNote  in
            viewModel.isUpdateLocalization = true
            viewModel.updateLocalizationAPI(buildId: buildId, buildLocalizationId: localizationID, localization: releaseNote)
        },refreshBuildList: {
            viewModel.isUpdateLocalization = true
            viewModel.getBuildsFromAPI(for: selectedApp.id, version: selectedVersion)
        }).environmentObject(viewModel)
    }
}

#Preview {
    VersionAndBuildsView()
}
