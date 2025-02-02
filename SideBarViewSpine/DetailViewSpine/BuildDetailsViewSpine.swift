//
//  BuildDetailsViewSpine.swift
//  App Store
//
//  Created by Nayan Bhut on 05/05/24.
//

import SwiftUI
import Spine

struct BuildDetailsViewSpine: View {
    @ObservedObject var viewModel: DetailViewSpineModel
    
    var getBuidsData:((String)-> Void)?
    var setBuidsData:((String, String, String)-> Void)?
    var refreshBuildList:(() -> Void)?
    
    var body: some View {
        VStack {
            if (viewModel.currentAppState == .appVersionBuildLoading) {
                SpinnerView()
            } else if ((viewModel.currentAppState == CurrentAppState.appVersionLoading) || (viewModel.currentAppState == CurrentAppState.appListLoading)) {
                
            } else {
                HStack {
                    Text("Builds").font(.title)
                    Text("Total Buids : \(viewModel.arrBuilds.count)")
                    Button(action: {
                        self.viewModel.isBuildsLoaded = false
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
        }
        .padding()
    }
    
    func getDate(dateString: NSDate?) -> String {
        guard let dateString = dateString else { return "" }
        
        let newFormatter = ISO8601DateFormatter()
        guard let date = newFormatter.date(from: dateString.description) else { return "" } // Get Date for UTC
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
    
    private func getCurrentBuildColor(processingState: String) -> (String, Color) { // PROCESSING, FAILED, INVALID, VALID
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
            List(viewModel.arrBuilds) { build in
                VStack(alignment: .leading) {
                    HStack {
                        Text("\(viewModel.selectedVersion?.version ?? "")(\(build.version ?? ""))")
                        Text("\(getDate(dateString: build.uploadedDate))")
                        Text(getCurrentBuildColor(processingState: build.processingState ?? "").0)
                            .foregroundColor(getCurrentBuildColor(processingState: build.processingState ?? "").1)
                        Text("\(convertDate(string:build.uploadedDate?.description ?? "") ?? "")").foregroundColor(.green)
                        //
                        if viewModel.currentAppState == .appLocalizationLoading {
                            SpinnerView()
                        } else {
                            Text("Update").onTapGesture {
                                guard let buildIndex = viewModel.arrBuilds.firstIndex(where: {$0.id == build.id}),
                                      let betaBuildLocalization = self.viewModel.arrBuilds[buildIndex].betaBuildLocalizations?.resources[0] as? BuildLocalizations,
                                      let localization = betaBuildLocalization.whatsNew else { return }
                                viewModel.createOrUpdate(buildLocalization: betaBuildLocalization, localization: localization, buildIndex:buildIndex)
                            }
                        }
                    }
                    
                    //                GeometryReader { proxy in
                    //                    VStack {
                    //                        Text("\(proxy.frame(in: .global).width)")
                    //                        ScrollView {
                    //                            LazyHGrid(rows: rows, spacing: 20) {
                    //                                ForEach(build.betaBuildLocalizations?.resources as? [BuildLocalizations] ?? []) { item in
                    //                                    TextEditor(text: .init(
                    //                                        get: { (build.betaBuildLocalizations?.resources[0] as? BuildLocalizations)?.whatsNew ?? ""},
                    //                                        set: { text in
                    //                                            if let buildIndex = viewModel.arrBuilds.firstIndex(where: {$0.id == build.id}) {
                    //                                                (self.viewModel.arrBuilds[buildIndex].betaBuildLocalizations?.resources[0] as? BuildLocalizations)?.whatsNew = text
                    //                                            }
                    //                                        }
                    //                                    ))
                    //                                    .scrollContentBackground(.hidden) // <- Hide it
                    //                                    .background(.red) // To see this
                    //                                }
                    //                            }
                    //                        }
                    //                    }
                    //                }.frame(height: 200)
                    
                    TextEditor(text: .init(
                        get: {
                            if build.betaBuildLocalizations?.resources.count ?? 0 > 0 {
                                return (build.betaBuildLocalizations?.resources[0] as? BuildLocalizations)?.whatsNew ?? ""
                            }else {
                                return ""
                            }
                        },
                        set: { text in
                            if let buildIndex = viewModel.arrBuilds.firstIndex(where: {$0.id == build.id}) {
                                if self.viewModel.arrBuilds[buildIndex].betaBuildLocalizations?.resources.count ?? 0 > 0 {
                                    (self.viewModel.arrBuilds[buildIndex].betaBuildLocalizations?.resources[0] as? BuildLocalizations)?.whatsNew = text
                                }else {
                                    let betaBuildLocalization = BuildLocalizations(whatsNew: text, locale: "en-US")
                                    let resourceColletion = ResourceCollection(resources: [betaBuildLocalization])
                                    self.viewModel.arrBuilds[buildIndex].betaBuildLocalizations?.appendResources(resourceColletion.resources)
                                }
                            }
                        }
                    ))
                    .frame(height: 50)
                    .padding(.vertical, 5)
                    .cornerRadius(10.0)
                    .border(Color.white)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    
                }.onAppear {
                    //                getBuidsData?(build.id)
                }
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

#Preview {
    BuildDetailsViewSpine(viewModel: DetailViewSpineModel(selectedApp: nil, arrVersions: [], currentTeam: .appName, currentAppState: .appListLoading))
}
