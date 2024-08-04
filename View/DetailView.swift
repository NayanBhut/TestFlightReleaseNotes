//
//  DetailView.swift
//  App Store
//
//  Created by Nayan Bhut on 19/04/24.
//

import SwiftUI

struct DetailView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    var body: some View {
        VStack {
            Text("DetailView")
            Text("Versions")
                .font(.title)
            loadVersion()
        }
    }
    
    @ViewBuilder private func loadVersion() -> some View {
        if viewModel.isAppVersionsLoaded {
            versionView()
        } else {
            SpinnerView()
        }
    }
    
    
    private func versionView() -> some View {
        HStack {
            versionList()
        }
        .padding(15)
        .onAppear {
            print("Selected App Name is \n", viewModel.getSelectedApp()?.app.attributes?.name ?? "")
            print("Total Version is \n", viewModel.getSelectedApp()?.arrVersions.count ?? "0")
            print("Total Builds is \n", viewModel.getSelectedVersion()?.arrBuilds.count ?? "0")
        }
    }
    
    private func versionList() -> some View {
        ForEach(viewModel.getSelectedApp()?.arrVersions ?? [], content: { version in
            VStack {
                versionsNumber(version: version)
                    .onTapGesture {
                        viewModel.setSelectedVersionAndGetBuilds(version: version.version)
                    }
            }.background(version.isSelected ? Color.purple : Color.clear)
        })
    }
    
    private func versionsNumber(version: VersionDataModel) -> some View {
        Text("\(version.version.attributes?.version ?? "")")
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
            .background(version.isSelected ? Color.purple : Color.white)
            .foregroundColor(Color.black)
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
    DetailView()
}
