//
//  ContentViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 18/08/23.
//

import Foundation
import AppStoreConnect_Swift_SDK

final class ContentViewModel: ObservableObject {
    @Published var apps: [AppModel] = []
    
    @Published var arrApps: [AppDataModel] = []
    var selectedAppAndVersionIndex: (Int?, Int?) = (nil, nil)
    
    @Published var currentTeam: Team = .appName
    
    @Published var isAppLoaded: Bool = false // App List
    @Published var isAppVersionsLoaded: Bool = false // App Versions
    @Published var isAppBuildsLoaded: Bool = false // Version Builds
    @Published var isUpdateLocalization: Bool = false // Update localization

    private var configuration: APIConfiguration!
    private var provider: APIProvider!
    
    @Published var currentAppState: CurrentAppState = .appListLoading {
        didSet {
            print("Value changed to \(currentAppState)")
        }
        willSet {
            print("Value changed from \(currentAppState)")
        }
    }
    
    init() {
        configuration = APIConfiguration(issuerID: currentTeam.getIssuerId(), privateKeyID: currentTeam.getPrivateKeyID(), privateKey: currentTeam.getPrivateKey())
        provider = APIProvider(configuration: configuration)
    }
    
    func updateTeam() {
        configuration = APIConfiguration(issuerID: currentTeam.getIssuerId(), privateKeyID: currentTeam.getPrivateKeyID(), privateKey: currentTeam.getPrivateKey())
        provider = APIProvider(configuration: configuration)
        getAllApps()
    }
    
    func setSelectedAppAndGetVersions(app: AppDataModel) {
        isAppVersionsLoaded = false
        
        arrApps = arrApps.map({ model in
            var appModel = model
            appModel.isExpanded = false
            return appModel
        })
        if let appIndex = arrApps.firstIndex(where: {$0.id == app.id}) {
            arrApps[appIndex].isExpanded = true
            selectedAppAndVersionIndex.0 = appIndex
        }
        
        loadAppsTestflightVersions(appId: getSelectedApp()?.id ?? "")
    }
    
    @MainActor
    func setSelectedVersionAndGetBuilds(version: PrereleaseVersion) {
        if let selectedAppIndex = arrApps.firstIndex(where: {$0.id == getSelectedApp()?.id}) {
            var arrVersions = arrApps[selectedAppIndex].arrVersions
            
            arrVersions = arrVersions.map({ model in
                var appModel = model
                appModel.isSelected = false
                return appModel
            })
            
            arrApps[selectedAppIndex].arrVersions = arrVersions
            if let versionIndex = arrVersions.firstIndex(where: {$0.id == version.id}) {
                arrApps[selectedAppIndex].arrVersions[versionIndex].isSelected = true
                self.selectedAppAndVersionIndex.1 = versionIndex
                getBuildsFromAPI(for: getSelectedApp()?.id ?? "", version: arrVersions[versionIndex])
            }
        }
    }
    
    func getSelectedVersion() -> VersionDataModel? {
        return getSelectedApp()?.arrVersions.first(where: {$0.isSelected == true}) ?? nil
    }
    
    func getSelectedApp() -> AppDataModel? {
        return arrApps.first(where: {$0.isExpanded})
    }
}

//MARK: - Update Data to View
extension ContentViewModel {
    @MainActor
    private func updateApps(to apps: [AppStoreConnect_Swift_SDK.App]) {
        self.arrApps = apps.map({ AppDataModel(id: $0.id, app: $0, arrVersions: []) })
    }

    @MainActor
    private func updateBuildLocalization(to buildsData: BetaBuildLocalization, buildId: String, localizeId: String) {
        // Update Model with localization
        if let appIndex = selectedAppAndVersionIndex.0, let versionIndex = selectedAppAndVersionIndex.1, let buidIndex = arrApps[appIndex].arrVersions[versionIndex].arrBuilds.firstIndex(where: {$0.id == buildId}) {
            isUpdateLocalization = false
            arrApps[appIndex].arrVersions[versionIndex].arrBuilds[buidIndex].localization = [buildsData]
            currentAppState = ._none
        }else {
            print("Updated for API Also")
        }
    }
    
    @MainActor
    private func updateBuild(to buildsData: [BetaBuildLocalization], appId: String, buildId: String) {
        guard let index = apps.firstIndex(where: {$0.id == appId}) else { return }
        guard let buildIndex = apps[index].arrBuilds.firstIndex(where: {$0.id == buildId}) else { return }
        
        let build = apps[index].arrBuilds[buildIndex]
        let buildModel = BuildModel(id: build.id, build: build.build, localization: buildsData)
        apps[index].arrBuilds[buildIndex] = buildModel
        isUpdateLocalization = false
        currentAppState = ._none
        print("Total Apps Counts : ", apps.map({$0.arrBuilds.count}))
    }
}

//MARK: - API Calls
extension ContentViewModel {
    func getAllApps() {
        currentAppState = .appListLoading
        Task.detached {
            await MainActor.run {
                self.isAppLoaded = false
                self.isAppVersionsLoaded = false
                self.isAppBuildsLoaded = false
            }
            let request = APIEndpoint.v1.apps.get(parameters: .init(
                    sort: [.minusname],
                    fieldsApps: [.appInfos, .name, .bundleID, .appStoreVersions, .preReleaseVersions],
                    limit: 10,
                    include:[.appStoreVersions, .preReleaseVersions]
                ))
            
            do {
                let apps = try await self.provider.request(request).data
                print("Apps are ", apps.count)
                await MainActor.run {
                    self.isAppLoaded = true
                    self.currentAppState = ._none
                    self.updateApps(to: apps)
                }
            } catch {
                print("Something went wrong fetching the apps: \(error.localizedDescription)")
            }
        }
    }
    
    func loadAppsTestflightVersions(appId: String) {
        print("Selected App id is ", appId )
        currentAppState = .appVersionLoading
        
        Task.detached {
            let request = APIEndpoint
                .v1
                .preReleaseVersions.get(parameters: .init(
                    filterApp: [appId], sort:[.minusversion], fieldsPreReleaseVersions: [.version], limit: 5, fieldsApps: [.builds]
                ))
            
//        https:api.appstoreconnect.apple.com/v1/apps/1163601891?include=appStoreVersions,preReleaseVersions
            do {
                let arrPrereleaseVersion = try await self.provider.request(request).data
                print("PrereleaseVersion are ", arrPrereleaseVersion.count)
                await MainActor.run {
                    if let appIndex = self.arrApps.firstIndex(where: { $0.id == appId }) {
                        let arrVersions = arrPrereleaseVersion.map { preReleaseversion in
                            return VersionDataModel(id: preReleaseversion.id, version: preReleaseversion, arrBuilds: [])
                        }
                        let model = AppDataModel(id: appId, app: self.arrApps[appIndex].app, arrVersions: arrVersions, isExpanded: self.arrApps[appIndex].isExpanded)
                        self.arrApps[appIndex] = model
                        self.currentAppState = ._none
                        self.isAppVersionsLoaded = true
                    }
                }
            } catch {
                print("Something went wrong fetching the apps: \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    func getBuildsFromAPI(for appId: String, version: VersionDataModel) {
        Task.detached {
            await MainActor.run {
                self.currentAppState = .appVersionBuildLoading
                self.isAppBuildsLoaded = false
            }
            
            guard let strVersion = version.version.attributes?.version else { return }
            
            let request = APIEndpoint.v1.builds.get(parameters: APIEndpoint.V1.Builds.GetParameters(filterPreReleaseVersionVersion: [strVersion], filterApp: [appId],limit: 10, include:[.app, .betaBuildLocalizations,.appStoreVersion ,.preReleaseVersion], fieldsBetaBuildLocalizations: [.build,.locale,.whatsNew], fieldsPreReleaseVersions: [.version]))
            do {
                let buildAPI = try await self.provider.request(request)
                let builds = buildAPI.data
                var arrLocalizations: [BetaBuildLocalization] = []
                
                buildAPI.included?.forEach(){ includ in
                    switch includ {
                    case .betaBuildLocalization(let localization):
                        arrLocalizations.append(localization)
                    default:
                        break
                    }
                }
                
                let arrBuildModel = builds.map { build in
                    if let arrLocalizations: BetaBuildLocalization = arrLocalizations.first(where: {$0.id == build.relationships?.betaBuildLocalizations?.data?.first?.id}) {
                        return BuildDataModel(id: build.id, build: build, localization: [arrLocalizations])
                    }else {
                        return BuildDataModel(id: build.id, build: build, localization: [])
                    }
                }
                
                await MainActor.run {
                    if let selectedAppindex = self.selectedAppAndVersionIndex.0, let versionAppIndex = self.selectedAppAndVersionIndex.1 {
                        self.isAppBuildsLoaded = true
                        self.isUpdateLocalization = false
                        self.currentAppState = ._none
                        self.arrApps[selectedAppindex].arrVersions[versionAppIndex].arrBuilds = arrBuildModel
                    }
                }
            }catch {
                print("Builds data error is \(error.localizedDescription)")
            }
        }
    }
    
    func updateLocalizationAPI(buildId: String, buildLocalizationId: String, localization: String) {
        currentAppState = .appLocalizationLoading
        Task.detached {
            let request = APIEndpoint.v1.betaBuildLocalizations.id(buildLocalizationId).patch(BetaBuildLocalizationUpdateRequest(data: BetaBuildLocalizationUpdateRequest.Data(type: .betaBuildLocalizations, id: buildLocalizationId, attributes: BetaBuildLocalizationUpdateRequest.Data.Attributes(whatsNew: localization))))
            print("Set Localization data is ")
            do {
                let buildLocalization = try await self.provider.request(request).data
                print("Localization data is ", buildLocalization)
                await MainActor.run {
                    self.updateBuildLocalization(to: buildLocalization, buildId: buildId, localizeId: buildLocalization.id)
                }
            } catch {
                print("Localization data is ", error.localizedDescription)
            }
        }
    }
    
    func loadLocalizationfromAPI(appId: String, buildId: String) {
        currentAppState = .appLocalizationLoading
        Task.detached {
            let request = APIEndpoint.v1.builds.id(buildId).betaBuildLocalizations.get()
            print("Get Localization data is ")
            do {
                let buildData = try await self.provider.request(request).data
                print("Localization data is ", buildData)
                await MainActor.run {
                    self.currentAppState = ._none
                    self.updateBuild(to: buildData, appId: appId, buildId: buildId)
                }
            } catch {
                print("Localization data error is \(error.localizedDescription)")
            }
        }
    }
}

enum CurrentAppState {
    case appListLoading, appVersionLoading, appVersionBuildLoading, appLocalizationLoading, _none
    
    var description: String {
        switch self {
        case .appListLoading:
            return "appListLoading"
        case .appVersionLoading:
            return "appVersionLoading"
        case .appVersionBuildLoading:
            return "appVersionBuildLoading"
        case .appLocalizationLoading:
            return "appLocalizationLoading"
        case ._none:
            return "_none"
        }
    }
}
