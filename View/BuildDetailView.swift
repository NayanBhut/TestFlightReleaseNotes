//
//  BuildDetailView.swift
//  App Store
//
//  Created by Nayan Bhut on 19/04/24.
//

import SwiftUI

struct BuildDetailsView: View {
    @EnvironmentObject var viewModel: ContentViewModel
    
    var getBuidsData:((String)-> Void)?
    var setBuidsData:((String, String, String)-> Void)?
    var refreshBuildList:(() -> Void)?
    
    var body: some View {
        VStack {
            if (viewModel.currentAppState == .appVersionBuildLoading) {
                SpinnerView()
            } else {
                HStack {
                    Text("Builds").font(.title)
                    Text("Refresh Build List")
                    Button(action: {
                        refreshBuildList?()
                    }) {
                        Text("Refresh")
                    }
                    
                    if viewModel.currentAppState == .appVersionBuildLoading {
                        SpinnerView()
                    }
                }
                getBuildsList()
                    .disabled(!viewModel.isAppBuildsLoaded)
            }
        }
        .padding()
    }
    
    private func getBuildsList() -> some View {
        List(viewModel.getSelectedVersion()?.arrBuilds ?? []) { build in
            VStack(alignment: .leading) {
                HStack {
                    Text("\(viewModel.getSelectedVersion()?.version.attributes?.version ?? "")(\(build.build.attributes?.version ?? ""))")
                    Text("\(build.build.attributes?.processingState?.rawValue ?? "")")
                        .foregroundColor(.green)
                    Text("\(convertDate(string:build.build.attributes?.uploadedDate?.description ?? "") ?? "")").foregroundColor(.green)
                    
                    if viewModel.currentAppState == .appLocalizationLoading {
                        SpinnerView()
                    } else {
                        Text("Update").onTapGesture {
                            setBuidsData?(build.id, build.localization.first?.id ?? "", build.localization.first?.attributes?.whatsNew ?? "")
                        }
                    }
                }
                TextEditor(text: .init(
                    get: { build.localization.first?.attributes?.whatsNew ?? ""},
                    set: { text in
                        if let appIndex = viewModel.selectedAppAndVersionIndex.0, let versionIndex = viewModel.selectedAppAndVersionIndex.1 {
                            if let buildIndex = viewModel.arrApps[appIndex].arrVersions[versionIndex].arrBuilds.firstIndex(where: {$0.id == build.id}) {
                                var arrLocal = build.localization
                                arrLocal[0].attributes?.whatsNew = text
                                viewModel.arrApps[appIndex].arrVersions[versionIndex].arrBuilds[buildIndex].localization = arrLocal
                            }
                        }
                    }
                )).frame(height: 50)
                    .padding(.vertical, 5)
                    .cornerRadius(10.0)
                    .border(Color.white)
            }.onAppear {
                getBuidsData?(build.id)
            }
        }
    }
    
    
    private func convertDate(string: String, fromFormat: String = "yyyy-MM-dd HH:mm:ss Z", toFormat: String = "dd MMM HH:mm") -> String? {
        let formatter = DateFormatter()
        
        formatter.dateFormat = fromFormat
        guard let date = formatter.date(from: string) else { return nil }
        
        formatter.dateFormat = toFormat
        return formatter.string(from: date)
    }
    
}

#Preview {
    BuildDetailsView()
}
