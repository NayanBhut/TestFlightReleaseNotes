//
//  SideBarViewSpineModel.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI

class SideBarViewSpineModel: ObservableObject {
    @Published var currentTeam: Team = .appName
    @Published var isExpanded = false
    @Published var arrApps: [AppStoreApp] = []
    @Published var currentAppState: CurrentAppState = .appListLoading
    
    var getVersion: ( (AppStoreApp?, [PreReleaseVersions], Team, CurrentAppState) -> Void )?
    
    @Published var arrVersion: [PreReleaseVersions] = []
    @Published var selectedApp: AppStoreApp?
    
    @Published var isAppListLoaded = false
    
//    init(getVersion: ((AppStoreApp?, [PreReleaseVersions], Team, CurrentAppState) -> Void)?) {
//        self.getVersion = getVersion
//    }
    
    func getAllApps(for team: Team) {
        isAppListLoaded = false
        currentAppState = .appListLoading
        self.selectedApp = nil
        self.arrVersion = []
        self.getVersion?(self.selectedApp, self.arrVersion, self.currentTeam, self.currentAppState)
        SpineManager().getAllApps(for: team) { result, nextPageURL, meta  in
            self.currentAppState = ._none
            self.getVersion?(self.selectedApp, self.arrVersion, self.currentTeam, self.currentAppState)
            switch result {
            case .success(let success):
                print("Success Data is ", success)
                self.updateCurrentLiveVersion(responseApp: success as? [AppStoreApp] ?? [])
            case .failure(let failure):
                print("Failure Data is ", failure)
                self.updateCurrentLiveVersion(responseApp: [])
            }
            self.isAppListLoaded = true
        }
    }
    
    func updateCurrentLiveVersion(responseApp: [AppStoreApp]) {
        var arrData = responseApp.map { appData in
            let tempApp = appData
            
            let currentVersion = appData.appStoreVersions?.resources.first as? AppStoreVersions
            
            tempApp.currentLiveVersion = ((currentVersion?.id ?? ""),  currentVersion?.versionString ?? "Not Last Version")
            tempApp.currentState = currentVersion?.appVersionState ?? ""
            
            
            if let value = (appData.displayableVersions?.resources.first as? AppStoreVersions)?.storeIcon as? NSDictionary{
                let icon = IconAttributes(templateUrl: value.value(forKey: "templateUrl") as? String,
                               width: value.value(forKey: "width") as? NSNumber,
                               height: value.value(forKey: "height") as? NSNumber)
                print(icon)
            }
            
            return appData
        }
        
        arrData.sort(by: {
            return $0.currentState < $1.currentState
        })
        
        self.arrApps = arrData
        
        currentAppState = ._none
        self.getVersion?(self.selectedApp, self.arrVersion, self.currentTeam, self.currentAppState)
    }
    
    func updateTeam() {
        getAllApps(for: currentTeam)
    }
    
    func setSelectedAppAndGetVersions(app: AppStoreApp) {
        selectedApp = app
        getTestFlightVersions(app: app)
    }
    
    private func getTestFlightVersions(app: AppStoreApp) {
        if let index = self.arrApps.firstIndex(where: { $0.id == app.id}) {
            arrApps = arrApps.map({ app in
                let temp = app
                temp.isSelected = false
                return temp
            })
            
            arrApps[index].isSelected = true
        }
        
        currentAppState = .appVersionLoading
        self.getVersion?(self.selectedApp, self.arrVersion, self.currentTeam, self.currentAppState)
        SpineManager().getTestFlightVersions(for: app, for: currentTeam) { versionData, nextPageURL, meta in
            if (versionData.value?.count ?? 0) > 10 {
                self.arrVersion = Array((versionData.value as? [PreReleaseVersions] ?? [])[0...9])
            } else {
                self.arrVersion = versionData.value as? [PreReleaseVersions] ?? []
            }
            self.currentAppState = ._none
            self.getVersion?(self.selectedApp, self.arrVersion, self.currentTeam, self.currentAppState)
        }
    }
}
