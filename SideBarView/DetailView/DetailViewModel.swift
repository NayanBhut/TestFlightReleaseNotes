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
    @Published var currentTeam: Credential?
    @Published var selectedVersion: PreReleaseVersionsModel?
    @Published var arrBuilds: [BuildsModel] = []
    
    var selectedApp: AppsData?
    @Published var isBuildsLoaded = false
    
    @Published var nextPageCursor: String?
    @Published var meta: Meta?
    
    private var cancellables = Set<AnyCancellable>()
    
    
    init(sidebarViewModel: SideBarViewModel) {
        // Subscribe to sidebarViewModel's selectedItem changes
//        sidebarViewModel.$currentTeam
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] currentTeam in
//                self?.currentTeam = currentTeam
//            }
//            .store(in: &cancellables)
        
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
        
        if let cursor = cursor {
            queryParams["cursor"] = cursor
        }
        
        guard let request = APIClient.shared.getRequest(api: .get(name: .getVersionBuilds, queryParams: queryParams), apiVersion: .v1) else { return }
        
        currentAppState = .appVersionBuildLoading
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            self.isBuildsLoaded = true
            self.currentAppState = ._none
            
            switch result {
            case .success(let successData):
                do {
                    let model = try getDecoder().decode(BuildsDocument.self, from: successData)
                    self.selectedVersion = version
                    
                    if cursor != nil {
                        self.arrBuilds += model.data
                    } else {
                        self.arrBuilds = model.data
                    }
                    self.meta = model.meta
                    self.nextPageCursor = model.meta.paging.nextCursor
                } catch {
                    self.selectedVersion = version
                    self.arrBuilds = []
                    self.meta = nil
                }
            case .failure:
                self.selectedVersion = version
                self.arrBuilds = []
                self.meta = nil
            }
        }
    }
    
    func updateBuildWhatsNew(buildId: String, whatsNew: String) {
        guard let buildIndex = arrBuilds.firstIndex(where: { $0.id == buildId }) else { return }
        
        if arrBuilds[buildIndex].betaBuildLocalizations.isEmpty {
            let betaBuildLocalization = BuildLocalizationsModel(
                id: buildId,
                locale: Constants.defaultLocale,
                whatsNew: whatsNew
            )
            arrBuilds[buildIndex].betaBuildLocalizations.append(betaBuildLocalization)
        } else {
            arrBuilds[buildIndex].betaBuildLocalizations[0].whatsNew = whatsNew
        }
    }
    
    func saveBuildLocalization(buildId: String) {
        guard let buildIndex = arrBuilds.firstIndex(where: { $0.id == buildId }),
              let betaBuildLocalization = arrBuilds[buildIndex].betaBuildLocalizations.first,
              let localization = betaBuildLocalization.whatsNew else { return }
        
        createOrUpdate(buildLocalization: betaBuildLocalization, localization: localization, buildIndex: buildIndex)
    }
}

// Constants
private enum Constants {
    static let defaultLocale = "en-US"
}

extension DetailViewModel {
    func createOrUpdate(buildLocalization: BuildLocalizationsModel, localization: String, buildIndex: Int) {
        // Prevent duplicate API calls
        guard currentAppState != .appLocalizationLoading else { return }
        
        let arrLocalizations = arrBuilds[buildIndex].betaBuildLocalizations
        if arrLocalizations.isEmpty {
            createBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex: buildIndex)
        } else {
            updateBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex: buildIndex)
        }
    }
    
    private func updateBuildLocalization(buildLocalization: BuildLocalizationsModel, localization: String, buildIndex: Int) {
        let model = BuildLocalizationsModel.updateBody(id: buildLocalization.id, whatsNew: buildLocalization.whatsNew)
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model),
              let request = APIClient.shared.getRequest(api: .patch(name: .postReleaseNote, body: data, path: buildLocalization.id), apiVersion: .v1) else {
            return
        }
        
        currentAppState = .appLocalizationLoading
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            self.currentAppState = ._none
            
            switch result {
            case .success(let successData):
                do {
                    let model = try getDecoder().decode(BuildLocalizationsModel.self, from: successData)
                    
                    guard buildIndex < self.arrBuilds.count else { return }
                    let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations
                    
                    if let index = arrLocalizations.firstIndex(where: { $0.id == model.id }) {
                        let buildLocalizationsModel = BuildLocalizationsModel(
                            id: model.id,
                            locale: model.locale,
                            whatsNew: model.whatsNew
                        )
                        self.arrBuilds[buildIndex].betaBuildLocalizations[index] = buildLocalizationsModel
                    }
                } catch {
                    // Handle error
                }
            case .failure:
                // Handle error
                break
            }
        }
    }
    
    private func createBuildLocalization(buildLocalization: BuildLocalizationsModel, localization: String, buildIndex: Int) {
        let model = BuildLocalizationsModel.createBody(
            locale: Constants.defaultLocale,
            whatsNew: buildLocalization.whatsNew,
            build: RelationshipOne(id: arrBuilds[buildIndex].id)
        )
        let encoder = JSONAPIEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(model),
              let request = APIClient.shared.getRequest(api: .post(name: .postReleaseNote, body: data), apiVersion: .v1) else {
            return
        }
        
        currentAppState = .appLocalizationLoading
        
        APIClient.shared.callAPI(with: request) { [weak self] result in
            guard let self = self else { return }
            
            self.currentAppState = ._none
            
            switch result {
            case .success(let successData):
                do {
                    let model = try getDecoder().decode(BuildLocalizationsModel.self, from: successData)
                    
                    guard buildIndex < self.arrBuilds.count else { return }
                    
                    let buildLocalizationsModel = BuildLocalizationsModel(
                        id: model.id,
                        locale: model.locale,
                        whatsNew: model.whatsNew
                    )
                    
                    // Replace the temporary localization with the real one from API
                    if self.arrBuilds[buildIndex].betaBuildLocalizations.isEmpty {
                        self.arrBuilds[buildIndex].betaBuildLocalizations.append(buildLocalizationsModel)
                    } else {
                        self.arrBuilds[buildIndex].betaBuildLocalizations[0] = buildLocalizationsModel
                    }
                } catch {
                    // Handle error
                }
            case .failure:
                // Handle error
                break
            }
        }
    }
}
