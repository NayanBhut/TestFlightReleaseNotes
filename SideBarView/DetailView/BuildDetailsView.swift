//
//  BuildDetailsView.swift
//  App Store
//
//  Created by Nayan Bhut on 05/05/24.
//

import SwiftUI

struct BuildDetailsView: View {
    @ObservedObject var viewModel: DetailViewModel
    
    var getBuidsData:((String)-> Void)?
    var setBuidsData:((String, String, String)-> Void)?
    var refreshBuildList:(() -> Void)?
    var loadMoreBuild:(() -> Void)?
    
    var body: some View {
        VStack {
            if (viewModel.currentAppState == .appVersionBuildLoading) {
                SpinnerView()
            } else if ((viewModel.currentAppState == CurrentAppState.appVersionLoading) || (viewModel.currentAppState == CurrentAppState.appListLoading)) {
                
            } else {
                HStack {
                    Text("Builds").font(.title)
                    Text("Total Buids : \(viewModel.meta?.paging.total ?? 0)")
                    
                    Button(action: {
                        self.viewModel.isBuildsLoaded = false
                        self.viewModel.nextPageCursor = nil
                        self.viewModel.meta = nil
                        refreshBuildList?()
                    }) {
                        Text("Refresh")
                    }
                    
                    if viewModel.currentAppState == .appVersionBuildLoading {
                        SpinnerView()
                    }
                }
                if viewModel.selectedVersion != nil {
                    getBuildsList()
                } else {
                    Spacer().frame(height: 100)
                    Text("Please select version above to get builds")
                }
            }
            
            if viewModel.nextPageCursor != nil {
                Button(action: {
                    loadMoreBuild?()
                }) {
                    Text("Load More")
                }
            }
        }
        .padding()
    }
    
    private func getDate(dateString: NSDate?) -> String {
        guard let dateString = dateString else { return "" }
        
        let newFormatter = ISO8601DateFormatter()
        guard let date = newFormatter.date(from: dateString.description) else { return "" } // Get Date for UTC
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func getDate(dateString: String?) -> String {
        guard let dateString = dateString else { return "" }
        
        let newFormatter = ISO8601DateFormatter()
        guard let date = newFormatter.date(from: dateString.description) else { return "" } // Get Date for UTC
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func getCurrentBuildColor(processingState: String, isExpired: Bool) -> (String, Color) { // PROCESSING, FAILED, INVALID, VALID
        if isExpired {
            return ("EXPIRED", .red)
        }
        
        switch processingState {
        case "PROCESSING":
            return ("PROCESSING", .yellow)
        case "FAILED":
            return ("FAILED", .red)
        case "INVALID":
            return ("INVALID", .orange)
        case "VALID":
            return ("VALID", .green)
        default:
            return ("", .clear)
        }
    }
    
    @ViewBuilder private func getBuildsList() -> some View {
        if viewModel.isBuildsLoaded {
            List(viewModel.arrBuilds, id: \.id) { build in
                BuildRowView(build: build, viewModel: viewModel, getDate: getDate, getCurrentBuildColor: getCurrentBuildColor, convertDate: convertDate)
            }
        } else {
            SpinnerView()
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

// Separate view to handle TextEditor state properly
struct BuildRowView: View {
    let build: BuildsModel
    @ObservedObject var viewModel: DetailViewModel
    let getDate: (String?) -> String
    let getCurrentBuildColor: (String, Bool) -> (String, Color)
    let convertDate: (String, String, String) -> String?
    
    @State private var whatsNewText: String = ""
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("\(viewModel.selectedVersion?.version ?? "")(\(build.version ?? ""))")
                Text("\(getDate(build.uploadedDate))")
                Text(getCurrentBuildColor(build.processingState ?? "", build.expired ?? false).0)
                    .foregroundColor(getCurrentBuildColor(build.processingState ?? "", build.expired ?? false).1)
                Text("\(convertDate(build.uploadedDate?.description ?? "", "yyyy-MM-dd HH:mm:ss Z", "dd MMM HH:mm") ?? "")").foregroundColor(.green)
                
                if viewModel.currentAppState == .appLocalizationLoading {
                    SpinnerView()
                } else {
                    Text("Update").onTapGesture {
                        guard let buildIndex = viewModel.arrBuilds.firstIndex(where: {$0.id == build.id}),
                              let betaBuildLocalization = viewModel.arrBuilds[buildIndex].betaBuildLocalizations.first,
                              let localization = betaBuildLocalization.whatsNew else { return }
                        viewModel.createOrUpdate(buildLocalization: betaBuildLocalization, localization: localization, buildIndex:buildIndex)
                    }
                }
            }
            
            TextEditor(text: $whatsNewText)
                .font(.body)
                .frame(minHeight: 100, maxHeight: 150)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
                .scrollContentBackground(.hidden)
                .onChange(of: whatsNewText) { newValue in
                    if let buildIndex = viewModel.arrBuilds.firstIndex(where: {$0.id == build.id}) {
                        if viewModel.arrBuilds[buildIndex].betaBuildLocalizations.count > 0 {
                            viewModel.arrBuilds[buildIndex].betaBuildLocalizations[0].whatsNew = newValue
                        } else {
                            let buildID = viewModel.arrBuilds[buildIndex].id
                            let betaBuildLocalization = BuildLocalizationsModel(id: buildID, locale: "en-US", whatsNew: newValue)
                            viewModel.arrBuilds[buildIndex].betaBuildLocalizations.append(betaBuildLocalization)
                        }
                    }
                }
                .onAppear {
                    if build.betaBuildLocalizations.count > 0 {
                        whatsNewText = build.betaBuildLocalizations.first?.whatsNew ?? ""
                    }
                }
        }
    }
}

#Preview {
    BuildDetailsView(viewModel: DetailViewModel(sidebarViewModel: SideBarViewModel()))
}
