//
//  DetailViewModel.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI
import Combine
import JSONAPI

enum CurrentAppState {
    case appListLoading, appVersionLoading, appVersionBuildLoading, appLocalizationLoading, _none
}

class DetailViewModel: ObservableObject {
    @Published var currentAppState: CurrentAppState = .appListLoading
    @Published var arrVersions: [PreReleaseVersionsModel] = []
    @Published var currentTeam: Team = .appName
    @Published var selectedVersion: PreReleaseVersionsModel?
    @Published var arrBuilds: [BuildsModel] = []
    
    var selectedApp: AppsData?
    @Published var isBuildsLoaded = false
    
    @Published var nextPageCursor: String?
    @Published var meta: Meta?
    
    private var cancellables = Set<AnyCancellable>()
    
    
    init(sidebarViewModel: SideBarViewModel) {
        // Subscribe to sidebarViewModel's selectedItem changes
        sidebarViewModel.$currentTeam
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentTeam in
                self?.currentTeam = currentTeam
            }
            .store(in: &cancellables)
        
        sidebarViewModel.$arrVersion
            .receive(on: DispatchQueue.main)
            .sink { [weak self] arrVersion in
                self?.arrVersions = arrVersion
            }
            .store(in: &cancellables)
        
        sidebarViewModel.$currentAppState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] currentAppState in
                self?.currentAppState = currentAppState
            }
            .store(in: &cancellables)
        
        sidebarViewModel.$selectedApp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedApp in
                self?.selectedApp = selectedApp
                self?.arrBuilds = []
                self?.arrVersions = []
                self?.nextPageCursor = nil
                self?.meta = nil
            }
            .store(in: &cancellables)
        
    }
}

extension DetailViewModel {
    func setSelectedVersionAndGetBuilds(selectedVersion: PreReleaseVersionsModel, cursor: String? = nil) {
        isBuildsLoaded = false
        arrVersions = arrVersions.map { version in
            var tempVersion = version
            tempVersion.isSelected = tempVersion.id == selectedVersion.id
            return tempVersion
        }
        
        guard let app = selectedApp else { return }
        getBuilds(app: app, version: selectedVersion, cursor: cursor)
    }
    
    func getBuilds(app: AppsData, version: PreReleaseVersionsModel, cursor: String? = nil) {
        var queryParams = ["filter[app]": app.id,
                           "filter[preReleaseVersion]": version.id,
                           "sort": "-version",
                           "include": "appStoreVersion,betaBuildLocalizations,preReleaseVersion",
                           "limit": "5"]
        
        if cursor != nil {
            queryParams["cursor"] = cursor
        }
        
        guard let request = APIClient.shared.getRequest(team: currentTeam, api: .get(name: .getVersionBuilds, queryParams: queryParams), apiVersion: .v1) else { return }
        
        currentAppState = .appVersionBuildLoading
        
        APIClient.shared.callAPI(with: request) { result in
            self.isBuildsLoaded = true
            self.currentAppState = ._none
            self.meta = nil
            switch result {
            case .success(let successData):
                print("API Model getBuildsModel Data is ", successData)
                
                do {
                    let model = try getDecoder().decode(BuildsDocument.self, from: successData)
                    self.selectedVersion = version
                    
                    if self.nextPageCursor != nil {
                        self.arrBuilds += model.data
                    } else {
                        self.arrBuilds = model.data
                    }
                    self.meta = model.meta
                    self.nextPageCursor = model.meta.paging.nextCursor
                    print("Model data is ", model)
                } catch {
                    print("API Error is ")
                    self.selectedVersion = version
                    self.arrBuilds = []
                }
            case .failure(let failure):
                print("API Error is ", failure)
                self.selectedVersion = version
                self.arrBuilds = []
            }
        }
    }
}

extension DetailViewModel {
    func createOrUpdate(buildLocalization: BuildLocalizationsModel, localization: String, buildIndex: Int) {
        let arrLocalizations =  arrBuilds[buildIndex].betaBuildLocalizations
        if arrLocalizations.count == 0 {
            createBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex:buildIndex)
        } else {
            updateBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex:buildIndex)
        }
    }
    
    func updateBuildLocalization(buildLocalization: BuildLocalizationsModel, localization: String, buildIndex: Int) {
        let model = BuildLocalizationsModel.updateBody(id: buildLocalization.id, whatsNew: buildLocalization.whatsNew)
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model) else { return }
        
        currentAppState = .appLocalizationLoading
        
        guard let request = APIClient.shared.getRequest(team: currentTeam, api: .patch(name: .postReleaseNote, body: data, path: buildLocalization.id), apiVersion: .v1) else { return }
        
        APIClient.shared.callAPI(with: request) { result in
            switch result {
            case .success(let successData):
                self.currentAppState = ._none
                print("API Model getBuildsModel Data is ", successData)
                
                do {
                    let model = try getDecoder().decode(BuildLocalizationsModel.self, from: successData)
                    let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations
                    
                    if let index = arrLocalizations.firstIndex(where: { $0.id == model.id}) {
                        let buildLocalizationsModel = BuildLocalizationsModel(id: model.id, locale: model.locale, whatsNew: model.whatsNew)
                        self.arrBuilds[buildIndex].betaBuildLocalizations[index] = buildLocalizationsModel
                    }
                    
                    print("Model data is ", model)
                } catch {
                    print("API Error is ")
                }
            case .failure(let failure):
                print("API Error is ", failure)
            }
        }
    }
    
    func createBuildLocalization(buildLocalization: BuildLocalizationsModel, localization: String, buildIndex: Int) {
        let model = BuildLocalizationsModel.createBody(locale: "en-US", whatsNew: buildLocalization.whatsNew, build: RelationshipOne(id: arrBuilds[buildIndex].id))
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model),
              let request = APIClient.shared.getRequest(team: currentTeam, api: .post(name: .postReleaseNote, body: data), apiVersion: .v1) else { return }
        
        currentAppState = .appLocalizationLoading
        
        APIClient.shared.callAPI(with: request) { result in
            self.currentAppState = ._none
            switch result {
            case .success(let successData):
                print("API Model getBuildsModel Data is ", successData)
                
                do {
                    let model = try getDecoder().decode(BuildLocalizationsModel.self, from: successData)
                    
                    let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations
                    if let index = arrLocalizations.firstIndex(where: { $0.id == model.id}) {
                        let buildLocalizationsModel = BuildLocalizationsModel(id: model.id, locale: model.locale, whatsNew: model.whatsNew)
                        self.arrBuilds[buildIndex].betaBuildLocalizations[index] = buildLocalizationsModel
                    }
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
