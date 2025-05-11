//
//  DetailViewSpine.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI

struct DetailViewSpine: View {
    @ObservedObject var viewModel: DetailViewSpineModel
    
    init(viewModel: DetailViewSpineModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        VStack {
            Text("DetailView \(viewModel.arrVersions.count)")
            Text("Versions")
                .font(.title)
            loadVersion()
            getBuildList()
            Spacer()
        }
    }
    
    @ViewBuilder private func loadVersion() -> some View {
        if ((viewModel.currentAppState == CurrentAppState.appVersionLoading) || (viewModel.currentAppState == CurrentAppState.appListLoading)) {
            SpinnerView()
        } else {
            versionView()
        }
    }
    
    private func versionView() -> some View {
        HStack {
            versionList()
        }
        .padding(15)
        .onAppear {
            print("Selected App Name is \n", viewModel.selectedApp?.name ?? "")
            print("Total Version is \n", viewModel.arrVersions.count)
        }
    }
    
    private func versionList() -> some View {
        ForEach(viewModel.arrVersions, content: { version in
            VStack {
                versionsNumber(version: version)
                    .onTapGesture {
                        viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version)
                    }
            }.background(version.isSelected ? Color.purple : Color.clear)
        })
    }
    
    private func versionsNumber(version: PreReleaseVersions) -> some View {
        Text("\(version.version ?? "")")
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(version.isSelected ? Color.purple : Color.white)
            .foregroundColor(Color.black)
    }
    
    @ViewBuilder private func getBuildList() -> some View {
        if viewModel.selectedApp != nil {
            BuildDetailsViewSpine(viewModel: viewModel, refreshBuildList:  {
                guard let version = viewModel.selectedVersion else { return }
                viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version)
            }, loadMoreBuild: {
                guard let nextPage = viewModel.nextPageCursor, let version = viewModel.selectedVersion else { return }
                viewModel.setSelectedVersionAndGetBuilds(selectedVersion: version, cursor: nextPage)
            })
        } else {
            if viewModel.currentAppState == ._none {
                Text("Please select App Version from Side Bar")
            }
        }
    }
    
    func getAppFontStyle(isSelectedApp: Bool) -> any ShapeStyle {
        let colors: [Color] = isSelectedApp ? [.white] : [.black]
        
        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    DetailViewSpine(viewModel: DetailViewSpineModel(sidebarViewModel: SideBarViewSpineModel()))
}
