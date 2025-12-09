//
//  SideBarViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 02/05/24.
//

import SwiftUI
import JSONAPI

class SideBarViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var arrApps: [AppsData] = []
    @Published var appMeta: Meta?
    @Published var currentAppState: CurrentAppState = .appListLoading
    @Published var arrVersion: [PreReleaseVersionsModel] = []
    @Published var selectedApp: AppsData?
    
    @Published var isAppListLoaded = false
    @Published var isTeamChanged = false
    
    func getiOSApps(nextPage: String? = nil) {
        var queryParams = [
            "include": "appStoreVersions",
            "filter[appStoreVersions.platform]": "IOS",
            "sort": "-name",
            "fields[builds]": "icons",
            "limit": "10"
        ]
        
        if let nextPage = nextPage {
            queryParams["cursor"] = nextPage
        }
        
        guard let request = APIClient.shared.getRequest(api: .get(name: .getAllApps, queryParams: queryParams), apiVersion: .v1) else { return }
        
        isAppListLoaded = false
        currentAppState = .appListLoading
        selectedApp = nil
        arrVersion = []
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            self.currentAppState = ._none
            self.isAppListLoaded = true
            
            switch result {
            case .success(let successData):
                do {
                    let model = try getDecoder().decode(AppsDocument.self, from: successData)
                    self.updateCurrentLiveVersion(responseApp: model, nextPage: nextPage)
                } catch {
                    self.updateCurrentLiveVersion(responseApp: AppsDocument(
                        data: [],
                        meta: Meta(paging: Meta.Pagination(total: 0, limit: 0, nextCursor: nil))
                    ))
                }
            case .failure:
                self.updateCurrentLiveVersion(responseApp: AppsDocument(
                    data: [],
                    meta: Meta(paging: Meta.Pagination(total: 0, limit: 0, nextCursor: nil))
                ))
            }
        }
    }
    
    private func updateCurrentLiveVersion(responseApp: AppsDocument, nextPage: String? = nil) {
        let processedApps = responseApp.data.map { appData -> AppsData in
            var tempApp = appData
            let currentVersion = appData.appStoreVersions.first
            
            tempApp.currentLiveVersion = (
                currentVersion?.id ?? "",
                currentVersion?.versionString ?? "Not Last Version"
            )
            tempApp.currentState = currentVersion?.appVersionState ?? ""
            
            return tempApp
        }.sorted { $0.currentState < $1.currentState }
        
        if nextPage != nil {
            arrApps += processedApps
        } else {
            arrApps = processedApps
        }
        
        appMeta = responseApp.meta
        currentAppState = ._none
    }
    
    func updateTeam() {
        getiOSApps()
    }
    
    func setSelectedAppAndGetVersions(app: AppsData) {
        selectedApp = app
        getTestFlightVersions(app: app)
    }
    
    private func getTestFlightVersions(app: AppsData) {
        let queryParams = [
            "filter[app]": app.id,
            "sort": "-version"
        ]
        
        guard let request = APIClient.shared.getRequest(api: .get(name: .getAppVersions, queryParams: queryParams), apiVersion: .v1) else { return }
        
        // Update selection state
        if let index = arrApps.firstIndex(where: { $0.id == app.id }) {
            arrApps = arrApps.map { app in
                var temp = app
                temp.isSelected = false
                return temp
            }
            arrApps[index].isSelected = true
        }
        
        currentAppState = .appVersionLoading
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            self.currentAppState = ._none
            
            switch result {
            case .success(let successData):
                do {
                    let model = try getDecoder().decode([PreReleaseVersionsModel].self, from: successData)
                    
                    // Limit to 10 versions
                    self.arrVersion = model.count > 10 ? Array(model.prefix(10)) : model
                } catch {
                    self.arrVersion = []
                }
            case .failure:
                self.arrVersion = []
            }
        }
    }
}
