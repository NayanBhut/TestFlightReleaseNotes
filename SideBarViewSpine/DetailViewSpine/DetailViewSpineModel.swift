//
//  DetailViewSpineModel.swift
//  App Store
//
//  Created by Nayan Bhut on 04/05/24.
//

import SwiftUI
import Combine
import Spine

class DetailViewSpineModel: ObservableObject {
    @Published var currentAppState: CurrentAppState = .appListLoading
    @Published var arrVersions: [PreReleaseVersions] = []
    @Published var currentTeam: Team = .appName
    @Published var selectedVersion: PreReleaseVersions?
    @Published var arrBuilds: [Builds] = []
    
    var selectedApp: AppStoreApp?
    @Published var isBuildsLoaded = false
    
    @Published var nextPageCursor: String?
    @Published var meta: Metadata?
    
    private var cancellables = Set<AnyCancellable>()
    
    
    init(sidebarViewModel: SideBarViewSpineModel) {
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
            }
            .store(in: &cancellables)
        
    }
}

extension DetailViewSpineModel {
    func setSelectedVersionAndGetBuilds(selectedVersion: PreReleaseVersions, cursor: String? = nil) {
        isBuildsLoaded = false
        self.nextPageCursor = cursor
        arrVersions = arrVersions.map { version in
            let tempVersion = version
            tempVersion.isSelected = tempVersion.id == selectedVersion.id
            return tempVersion
        }
        
        guard let app = selectedApp else { return }
        getBuilds(app: app, version: selectedVersion, cursor: cursor)
    }
    
    func getBuilds(app: AppStoreApp, version: PreReleaseVersions, cursor: String? = nil) {
        currentAppState = .appVersionBuildLoading
        SpineManager().getVersionBuilds(for: app, for: version, for: currentTeam, cursor: cursor) { result, nextPageURL, meta in
            self.isBuildsLoaded = true
            self.currentAppState = ._none
            self.meta = nil
            switch result {
            case .success(let success):
                self.selectedVersion = version
                
                if self.nextPageCursor != nil {
                    self.arrBuilds += success as? [Builds] ?? []
                } else {
                    self.arrBuilds = success as? [Builds] ?? []
                }
                self.meta = meta
            case .failure(let failure):
                print(failure)
                self.selectedVersion = version
                self.arrBuilds = []
            }
            
            if let nextPageURL = nextPageURL, let cursor = URLComponents(url: nextPageURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: {$0.name == "cursor"}) { // Next Page
                print("Next Page URL is ", nextPageURL)
                self.nextPageCursor = cursor.value
            } else {
                self.nextPageCursor = nil
            }
        }
    }
}

extension DetailViewSpineModel {
    func createOrUpdate(buildLocalization: BuildLocalizations, localization: String, buildIndex: Int) {
        if let arrLocalizations =  arrBuilds[buildIndex].betaBuildLocalizations?.resources as? [BuildLocalizations] {
            if arrLocalizations.first(where: {$0.id != nil}) == nil {
                createBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex:buildIndex)
            } else {
                updateBuildLocalization(buildLocalization: buildLocalization, localization: localization, buildIndex:buildIndex)
            }
        }
    }
    
    func updateBuildLocalization(buildLocalization: BuildLocalizations, localization: String, buildIndex: Int) {
        currentAppState = .appLocalizationLoading
        SpineManager().updateBuildLocalization(for: currentTeam, localize: buildLocalization) { result, meta in
            self.currentAppState = ._none
            switch result {
            case .success(let success):
                print(success)
                if let updatedData = (success.first as? UpdateBuildLocalizations),
                   let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations?.resources  as? [BuildLocalizations],
                   let index = arrLocalizations.firstIndex(where: { $0.id == updatedData.id}) {
                    (self.arrBuilds[buildIndex].betaBuildLocalizations?.resources[index] as? BuildLocalizations)?.whatsNew = updatedData.whatsNew
                }
            case .failure(let failure):
                print(failure)
            }
        }
    }
    
    func createBuildLocalization(buildLocalization: BuildLocalizations, localization: String, buildIndex: Int) {
        currentAppState = .appLocalizationLoading
        SpineManager().createBuildLocalization(for: currentTeam, localize: buildLocalization, build: arrBuilds[buildIndex]) { result, meta in
            self.currentAppState = ._none
            switch result {
            case .success(let success):
                print(success)
                if let updatedData = (success.first as? UpdateBuildLocalizations),
                   let arrLocalizations = self.arrBuilds[buildIndex].betaBuildLocalizations?.resources  as? [BuildLocalizations],
                   let index = arrLocalizations.firstIndex(where: { $0.id == updatedData.id}) {
                    (self.arrBuilds[buildIndex].betaBuildLocalizations?.resources[index] as? BuildLocalizations)?.whatsNew = updatedData.whatsNew
                }
            case .failure(let failure):
                print(failure)
            }
        }
    }
}
