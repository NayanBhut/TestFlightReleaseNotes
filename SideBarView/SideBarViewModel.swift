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
    
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var selectedStateFilter: AppConfigs.AppStateFilter = .all {
        didSet { applyFilters() }
    }
    @Published var selectedSortOption: AppConfigs.SortOption = .nameDescending {
        didSet { applyFilters() }
    }
    @Published var filteredApps: [AppsData] = []
    
    private var allLoadedApps: [AppsData] = []
    
    func getiOSApps(nextPage: String? = nil) {
        var queryParams: [String: String] = [
            "include": "appStoreVersions,appStoreIcon",
            "filter[appStoreVersions.platform]": "IOS",
            "fields[builds]": "icons",
            "limit": String(AppConfigs.appListLimit)
        ]
        
        queryParams["sort"] = selectedSortOption.queryValue
        
        if !AppConfigs.filterName.isEmpty {
            queryParams["filter[name]"] = AppConfigs.filterName
        }
        
        if let stateFilter = selectedStateFilter.apiValue {
            queryParams["filter[appStoreVersions.appStoreState]"] = stateFilter
        }
        
	if let nextPage = nextPage {
            queryParams["cursor"] = nextPage
        }
        
guard let request = APIClient.shared.getRequest(api: .get(name: .getAllApps, queryParams: queryParams), apiVersion: .v1) else { return }
        
        DispatchQueue.main.async {
            self.isAppListLoaded = false
            self.currentAppState = .appListLoading
            self.selectedApp = nil
            self.arrVersion = []
        }
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
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
    }
    
    private func updateCurrentLiveVersion(responseApp: AppsDocument, nextPage: String? = nil) {
        let processedApps = responseApp.data.map { appData -> AppsData in
            var tempApp = appData
            let currentVersion = appData.appStoreVersions.first
            
            tempApp.currentLiveVersion = (
                currentVersion?.id ?? "",
                currentVersion?.versionString ?? "Not Last Version"
            )
            tempApp.currentState = currentVersion?.appStoreState ?? ""
            tempApp.iconURL = appData.appStoreIcon?.iconAsset?.templateUrl

            return tempApp
        }
        
        if nextPage != nil {
            allLoadedApps += processedApps
            arrApps = allLoadedApps
        } else {
            allLoadedApps = processedApps
            arrApps = processedApps
        }
        
        appMeta = responseApp.meta
        currentAppState = ._none
        applyFilters()
    }
    
    func applyFilters() {
        var filtered = allLoadedApps
        
        if !searchText.isEmpty {
            filtered = filtered.filter { app in
                (app.name ?? "").localizedCaseInsensitiveContains(searchText) ||
                (app.bundleId ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        if selectedStateFilter != .all {
            filtered = filtered.filter { app in
                app.currentState == selectedStateFilter.rawValue ||
                app.currentState.replacingOccurrences(of: "_", with: " ").uppercased() == selectedStateFilter.rawValue
            }
        }
        
        filtered = filtered.sorted { app1, app2 in
            switch selectedSortOption {
            case .nameAscending:
                return (app1.name ?? "") < (app2.name ?? "")
            case .nameDescending:
                return (app1.name ?? "") > (app2.name ?? "")
            case .stateAscending:
                return app1.currentState < app2.currentState
            case .stateDescending:
                return app1.currentState > app2.currentState
            }
        }
        
        filteredApps = filtered
    }
    
    func updateTeam() {
        allLoadedApps = []
        arrApps = []
        filteredApps = []
        searchText = ""
        AppConfigs.filterName = ""
        selectedStateFilter = .all
        getiOSApps()
    }
    
    func loadMoreApps(cursor: String) async {
        await MainActor.run {
            guard let nextCursor = self.appMeta?.paging.nextCursor else { return }
        }
        getiOSApps(nextPage: cursor)
    }
    
    func setSelectedAppAndGetVersions(app: AppsData) {
        selectedApp = app
        getTestFlightVersions(app: app)
    }
    
    private func getTestFlightVersions(app: AppsData) {
        let queryParams = [
            "filter[app]": app.id,
            "sort": "-version",
            "limit": String(AppConfigs.versionLimit)
        ]
        
        guard let request = APIClient.shared.getRequest(api: .get(name: .getAppVersions, queryParams: queryParams), apiVersion: .v1) else { return }
        
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
            
            DispatchQueue.main.async {
                self.currentAppState = ._none
                
                switch result {
                case .success(let successData):
                    do {
                        let model = try getDecoder().decode([PreReleaseVersionsModel].self, from: successData)
                        self.arrVersion = model
                    } catch {
                        self.arrVersion = []
                    }
                case .failure:
                    self.arrVersion = []
                }
            }
        }
    }
}
