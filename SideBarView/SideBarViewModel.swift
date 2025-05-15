//
//  SideBarViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI
import JSONAPI

class SideBarViewModel: ObservableObject {
    @Published var currentTeam: Team = .appName
    @Published var isExpanded = false
    @Published var arrApps: [AppsData] = []
    @Published var currentAppState: CurrentAppState = .appListLoading
    @Published var arrVersion: [PreReleaseVersionsModel] = []
    @Published var selectedApp: AppsData?
    
    @Published var isAppListLoaded = false
    
//    init(getVersion: ((AppsData?, [PreReleaseVersionsModel], Team, CurrentAppState) -> Void)?) {
//        self.getVersion = getVersion
//    }
    
    func getAllApps(for team: Team) {
        let queryParams = ["include": "appStoreVersions",
                           "filter[appStoreVersions.platform]": "IOS",
                           "sort": "-name",
                           "fields[builds]": "icons"
            
        ]
        
        guard let request = APIClient.shared.getRequest(team: team, api: .get(name: .getAllApps,queryParams: queryParams), apiVersion: .v1) else { return }
        
        isAppListLoaded = false
        currentAppState = .appListLoading
        self.selectedApp = nil
        self.arrVersion = []
        
        APIClient.shared.callAPI(with: request) { result in
            self.currentAppState = ._none
            switch result {
            case .success(let successData):
                print("API Model getAllApps Data is ", successData)
                
                do {
                    let model = try getDecoder().decode([AppsData].self, from: successData)
                    print("Model data is ", model)
                    self.updateCurrentLiveVersion(responseApp: model)
                } catch {
                    print("API Error is ")
                }
            case .failure(let failure):
                print("API Error is ", failure)
                self.updateCurrentLiveVersion(responseApp: [])
            }
            self.isAppListLoaded = true
        }
    }
    
    func updateCurrentLiveVersion(responseApp: [AppsData]) {
        var arrData = responseApp.map { appData in
            var tempApp = appData
            
            let currentVersion = appData.appStoreVersions.first
            
            tempApp.currentLiveVersion = ((currentVersion?.id ?? ""),  currentVersion?.versionString ?? "Not Last Version")
            tempApp.currentState = currentVersion?.appVersionState ?? ""
            
//            if let value = (appData.displayableVersions?.resources.first as? AppStoreVersions)?.storeIcon as? NSDictionary{
//                let icon = IconAttributes(templateUrl: value.value(forKey: "templateUrl") as? String,
//                               width: value.value(forKey: "width") as? NSNumber,
//                               height: value.value(forKey: "height") as? NSNumber)
//                print(icon)
//            }
            
            return tempApp
        }
        
        arrData.sort(by: {
            return $0.currentState < $1.currentState
        })
        
        self.arrApps = arrData
        
        currentAppState = ._none
    }
    
    func updateTeam() {
        getAllApps(for: currentTeam)
    }
    
    func setSelectedAppAndGetVersions(app: AppsData) {
        selectedApp = app
        getTestFlightVersions(app: app)
    }
    
    private func getTestFlightVersions(app: AppsData) {
        let queryParams = ["filter[app]": app.id,
                           "sort": "-version"]
        
        guard let request = APIClient.shared.getRequest(team: currentTeam, api: .get(name: .getAppVersions, queryParams: queryParams), apiVersion: .v1) else { return }
        
        if let index = self.arrApps.firstIndex(where: { $0.id == app.id}) {
            arrApps = arrApps.map({ app in
                var temp = app
                temp.isSelected = false
                return temp
            })
            
            arrApps[index].isSelected = true
        }
        
        currentAppState = .appVersionLoading
        
        APIClient.shared.callAPI(with: request) { result in
            switch result {
            case .success(let successData):
                print("API Model getBuildsModel Data is ", successData)
                
                do {
                    let model = try getDecoder().decode([PreReleaseVersionsModel].self, from: successData)
                    
                    if (model.count) > 10 {
                        self.arrVersion = Array(model[0...9])
                    } else {
                        self.arrVersion = model
                    }
                    
                    self.currentAppState = ._none
                    
                    print("Model data is ", model)
                } catch {
                    print("API Error is ")
                }
            case .failure(let failure):
                print("API Error is ", failure)
            }
        }
    }
}
